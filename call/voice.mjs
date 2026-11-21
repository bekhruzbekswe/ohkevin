// The call's listening and speaking: when it hears you, when it joins your pauses, when it waits, when the voice is cut
// off, and how the voice is played. Tuned by ear and checked against the Swift app, so it is frozen: a change here is a
// change in how a call feels (voice.replay.test.mjs replays recorded calls through it). It never touches the page.
// The host hands in everything it uses (clock, timers, server, recogniser, microphone, audio) and reads what it does:
//
//   const call = createCall(host)
//   in:  call.start(on)  call.mute(on)  call.hush()  call.typed(text)  call.server(event)  call.set({ headphones, voice })
//   out: call.state (live, read any time)  and  call.on(type, fn) for
//        'state'   (state)                something in call.state changed
//        'interim' (text)                 your words so far; '' clears them
//        'heard'   ({ text, replaces })   your words for a turn; replaces: they take the place of your last turn and what followed it
//        'spoken'  (text)                 a sentence of the voice started playing
//        'floor'   (lane, on, hollow)     'you' or 'voice' started or stopped (hollow: the voice is paused for a maybe)
//        'tally'   (entry)                one thing to count (stats.mjs)
//        'problem' (code, detail)         'old-server' | 'no-talk-over' | 'no-recognition' | 'recognition' { error, bySystem } | 'mic-ok'
//
// host: { ears (ears.mjs, or null), lang, voice, headphones, now(), setTimeout, clearTimeout, setInterval, clearInterval,
//         post(path, body) → Promise, tts(voice, text) → Promise<Response>, audioContext() → AudioContext,
//         Recognition (SpeechRecognition or undefined), getUserMedia(constraints), speech (speechSynthesis), Utterance }
export function createCall(host) {
  const E = host.ears, LANG = host.lang, post = host.post, now = host.now
  const { setTimeout, clearTimeout, setInterval, clearInterval, speech: speechSynthesis, Utterance: SpeechSynthesisUtterance } = host
  const fns = {}, emit = (type, ...a) => { for (const fn of fns[type] ?? []) fn(...a) }
  const refresh = () => emit('state', state), showSettings = refresh, showAsks = refresh
  const mark = (lane, on, hollow) => emit('floor', lane, on, hollow), tally = entry => emit('tally', entry), ghost = text => emit('interim', text)
  const problem = (code, detail) => emit('problem', code, detail)

  let live = false, muted = false, trackPath = null, ears = 0, speaking = false, hearing = false, thinking = false, tainted = false, heardAt = 0
  let rec = null, audio = null, headphones = !!host.headphones
  let track = null, src = null, analyser = null, levels = null, gate = null, levelTimer = 0, held = 0
  let aired = [], playing = null, overVoice = [], hushed = Promise.resolve()
  // Approving by voice (the rules are on the server, approve.mjs): the approval whose question is still playing, the one whose
  // question has finished and when, and when your current utterance began and whether the voice was talking then.
  let askNext = '', askHeard = '', askHeardAt = 0, utterAt = 0, utterOver = false
  const ASK_GUARD_MS = 300, ASK_FOR_MS = 20000 // a yes counts from this long after the question ends (recognition reports words late) until this long after
  // A pause to think (helpers in ears.mjs): your last spoken words stay open to more, and more words are joined to them.
  let pending = '', pendingAt = 0, turnState = '', joining = false, waitTimer = 0, nudged = false, stray = '', strayAt = 0
  let voices = [], voiceName = host.voice
  let epoch = 0, chain = Promise.resolve(), current = null, queued = 0
  let deniedBySystem = false
  // The voice's words of this turn, as the server sent them, until it ends or you speak; and its latest turn's words,
  // kept after the turn ends while the voice may still be playing them.
  let voiceText = null, turnText = ''

  // As each sentence starts playing. timing: { t0, dur } in AudioContext seconds, or { t0: null } for the browser voice.
  function began(text, timing) {
    askHeard = '' // the voice says something new: a yes now answers that, not the step
    if (turnState === 'sent' || turnState === 'waiting') { turnState = 'answering'; pendingAt = now() }
    if (!speaking) { aired = []; gate?.quiet(now(), E.TUNE.guardMs) } // a new spell of talking
    aired.push(text); playing = timing
    speaking = true; thinking = false; mark('voice', true); refresh()
    emit('spoken', text)
    if (heardAt) { tally({ kind: 'reply', delay: (now() - heardAt) / 1000 }); heardAt = 0 }
  }
  function ended() {
    setTimeout(() => {
      if (queued || speechSynthesis.speaking || speechSynthesis.pending) return
      speaking = false; mark('voice', false); refresh()
      if (askNext) { askHeard = askNext; askHeardAt = now(); askNext = '' }
      showAsks()
    }, 250)
  }
  function sayBrowser(text) {
    const u = new SpeechSynthesisUtterance(text)
    u.lang = LANG; u.rate = 1.05; u.onstart = () => began(text, { t0: null }); u.onend = () => { playing = null; ended() }; u.onerror = ended
    speechSynthesis.speak(u)
  }
  function say(text) {
    if (!audio || !voices.includes(voiceName)) return sayBrowser(text)
    const mine = epoch
    // Ask for the audio now so it is ready by the time the sentence before it has played.
    const clip = host.tts(voiceName, text)
      .then(r => (r.ok ? r.arrayBuffer() : Promise.reject())).then(b => audio.decodeAudioData(b)).catch(() => null)
    queued++
    chain = chain.then(async () => {
      const buf = await clip
      const t = now() // the answer to your last words does not start while you are still adding to them
      while (hearing && joining && turnState === 'sent' && mine === epoch && now() - t < E.TUNE.joinMs) await new Promise(r => setTimeout(r, 50))
      if (now() - t > 100) console.info(`[turn] answer held ${((now() - t) / 1000).toFixed(1)} s while you were still talking`)
      if (mine === epoch && buf) {
        await new Promise(done => {
          current = audio.createBufferSource(); current.buffer = buf; current.connect(audio.destination)
          current.onended = done; began(text, { t0: audio.currentTime, dur: buf.duration }); current.start()
        })
        playing = null
      }
      else if (mine === epoch) sayBrowser(text)
      current = null; queued--; ended()
    })
  }
  // What the developer has heard of the current spell of talking: whole sentences, plus the played share of the last.
  function heardSoFar() {
    if (!playing) return aired.join(' ')
    const part = playing.t0 == null || !E ? '' : E.cutText(aired.at(-1), (audio.currentTime - playing.t0) / playing.dur)
    return [...aired.slice(0, -1), part].filter(Boolean).join(' ')
  }
  function hush(cut = speaking || queued > 0) { // cut: something was still to be said, so tell the talker what was heard
    askNext = '' // a question cut off was not heard in full
    const heard = speaking ? heardSoFar() : ''
    epoch++
    try { current?.stop() } catch {}
    speechSynthesis.cancel()
    if (held) { clearTimeout(held); held = 0; audio.resume(); mark('you', false) }
    hushed = post('/hush', cut ? { heard } : {}).catch(() => {})
    speaking = false; mark('voice', false); refresh()
  }

  // ── ears ─────────────────────────────────────────────────────────────────────
  const HOT = /\b(stop|wait|hold on|pause|quiet|enough)\b/i
  function heard(text, ask = '', replaces = false) {
    ghost(''); voiceText = null; emit('heard', { text, replaces })
    heardAt = now(); thinking = true; refresh()
    hushed.then(() => post('/say', ask ? { text, ask } : { text })) // after any hush, so the talker learns it was cut off first
  }
  // Your final words for a turn. Words that add to a turn still open (ears.mjs stillOpen) are joined to it and sent whole.
  const JOINED = { sent: 'before its answer started', waiting: 'while the voice waited' }
  function said(text) {
    const echo = !!stray && now() - strayAt < E.TUNE.joinMs // a lone word heard over the voice goes in front of these
    if (echo) text = `${stray} ${text}` // a lone word you said over the voice just before
    stray = ''
    const both = joining && E.joinTurn(pending, text)
    if (both && turnState === 'sent') hush(true) // its answer has not played: drop it, and the talker is told it went unheard
    const replaces = !!both && turnState !== 'answering' // one thought, one bubble
    console.info(`[turn] ${both ? `joined ${JOINED[turnState]}` : 'usual'}`)
    if (both) tally({ kind: 'joined' })
    const since = utterAt - askHeardAt, fresh = !echo && !both && !utterOver && since >= ASK_GUARD_MS && since < ASK_FOR_MS
    heard(both || text, fresh ? askHeard : '', replaces)
    pending = both || text; pendingAt = now(); turnState = 'sent'; joining = false; nudged = false
  }
  // A lone word over the voice does not cut it off, but it is kept in case more words follow (see said()).
  function aside(word) { stray = word; strayAt = now() }
  // The voice is waiting for the rest of your thought. If you stay quiet for waitMs, it answers what it has.
  function waitMore() {
    clearTimeout(waitTimer)
    waitTimer = setTimeout(() => {
      if (turnState !== 'waiting') return
      if (hearing) return waitMore() // you are still talking: your words will come
      console.info('[turn] nothing more came: it answers what it has')
      turnState = 'sent'; pendingAt = now(); thinking = true; nudged = true; refresh()
      hushed.then(() => post('/say', { text: pending, done: true }))
    }, E?.TUNE.waitMs ?? 3000)
  }
  // SpeechRecognition.start(track) exists if a non-track argument throws a TypeError (checked in Chrome 157).
  // A browser without it ignores the argument and starts the microphone, so that probe is aborted.
  function takesTrack(SR) {
    const probe = new SR()
    try { probe.start({}) } catch (err) { return err instanceof TypeError }
    probe.abort()
    return false
  }

  // The recogniser normally takes the raw microphone, which also hears the voice. Chrome removes its own playback
  // from an echo-cancelled getUserMedia track, so on that track it can hear you while the voice talks.
  // Returns the track, or null to listen exactly as before.
  async function openEars(SR) {
    if (!E) { problem('old-server'); return null }
    if (!takesTrack(SR)) { problem('no-talk-over'); return null }
    let stream
    deniedBySystem = false
    try { stream = await host.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }) }
    catch (err) { deniedBySystem = /system/i.test(err.message); if (err.name !== 'NotAllowedError') problem('no-talk-over'); return null } // a blocked mic gets its own note from the recogniser
    const t = stream.getAudioTracks()[0], ec = t?.getSettings().echoCancellation
    if (ec !== true && ec !== 'all') { t?.stop(); problem('no-talk-over'); return null }
    src = audio.createMediaStreamSource(stream); analyser = audio.createAnalyser(); analyser.fftSize = 1024
    src.connect(analyser) // measured only, never played
    levels = new Float32Array(analyser.fftSize); gate = new E.Gate(); levelTimer = setInterval(watchLevel, 20)
    return t
  }
  function stopEars() {
    if (held) { clearTimeout(held); held = 0; audio.resume(); mark('you', false) } // e.g. a recogniser error during a pause
    clearInterval(levelTimer); src?.disconnect(); track?.stop()
    track = src = analyser = levels = gate = null
  }

  // Every 20 ms while the voice talks: a sustained level on the echo-cancelled mic pauses the voice at once.
  // Timers are not throttled while the tab is playing audio.
  function watchLevel() {
    if (!speaking || held || !voices.includes(voiceName)) return // the browser voice is played by macOS, outside the echo canceller
    analyser.getFloatTimeDomainData(levels)
    const db = E.levelDb(levels)
    if (gate.feed(db, now())) hold(db)
  }
  function hold(db) { // maybe someone is talking: freeze the voice mid-word until the recogniser confirms
    audio.suspend(); mark('you', true, true); held = setTimeout(release, E.TUNE.holdMs)
    console.info(`[ears] paused at ${db.toFixed(1)} dB`)
  }
  function release() { // no words came, so it was a noise: carry on from the same word
    held = 0; gate.miss(); gate.quiet(now(), E.TUNE.restMs); audio.resume(); mark('you', false)
    console.info(`[ears] no words, carrying on; bar now ${gate.bar} dB`)
    tally({ kind: 'nothing' })
  }

  async function listen() {
    const SR = host.Recognition
    if (!SR) return problem('no-recognition')
    const mine = ++ears
    track = await openEars(SR)
    if (!live || muted || mine !== ears) return stopEars() // the call ended, or the mic was muted, while it was opening
    trackPath = !!track; showSettings()
    rec = new SR(); rec.continuous = true; rec.interimResults = true; rec.lang = LANG
    overVoice = []
    rec.onresult = e => {
      if (muted) return
      if (E?.TUNE.joinMs > 0) overVoice.length = e.results.length // Chrome briefly splits a result in two; a later utterance may reuse that number
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const r = e.results[i], over = speaking
        let text = r[0].transcript.trim()
        if (track && voices.includes(voiceName)) {
          // Echo-cancelled ears: words heard over the voice are the developer's, once any leaked echo of it is removed.
          overVoice[i] ??= speaking // whether this utterance began while the voice was talking
          if (overVoice[i]) text = E.userPart(text, aired.join(' '))
          if (!text) { if (r.isFinal) { if (!/\s/.test(r[0].transcript.trim())) aside(r[0].transcript.trim()); hearing = false; mark('you', false); ghost(''); refresh() } continue }
          if (speaking) {
            if (!held && !E.isStopOnly(text) && text.split(/\s+/).length < 2) { if (r.isFinal) aside(text); continue } // one stray word over the voice is not enough
            console.info('[ears] cut off by', JSON.stringify(text))
            tally({ kind: 'cut' })
            hush()
          }
          if (r.isFinal && overVoice[i] && E.isStopOnly(text)) { hearing = false; mark('you', false); ghost(''); refresh(); continue } // "stop" only cuts it
        } else if (speaking) {
          if (headphones) {
            if (text.split(/\s+/).length < 2) continue
            hush() // on headphones, two words from you cut it off and count as your turn
          } else {
            // On speakers the microphone also hears the voice, so what it hears while talking does not count,
            // except a stop word that the voice itself is not saying.
            if (HOT.test(text) && !HOT.test(turnText)) hush()
            tainted = !r.isFinal
            continue
          }
        }
        if (!hearing) { joining = !!E?.stillOpen(turnState, now() - pendingAt); utterAt = now(); utterOver = over || !!overVoice[i] } // a new utterance: does it add to your last words? did it start over the voice?
        if (!r.isFinal) { hearing = true; mark('you', true); ghost(text); refresh(); continue }
        hearing = false; mark('you', false); refresh()
        if (tainted) { tainted = false; ghost(''); continue }
        if (text) said(text)
      }
    }
    rec.onerror = e => {
      if (e.error === 'no-speech' || e.error === 'aborted') return
      live = false; stopEars(); muted = false; refresh()
      problem('recognition', { error: e.error, bySystem: deniedBySystem })
    }
    rec.onaudiostart = () => problem('mic-ok') // it hears
    const me = rec
    rec.onend = () => {
      if (rec !== me) return // a recogniser stopped by a mute ends late, after an unmute has started the next one
      hearing = false; mark('you', false); overVoice = []
      if (track && track.readyState !== 'live') { stopEars(); problem('no-talk-over') } // the microphone went away: listen as before
      if (live && !muted) try { track ? rec.start(track) : rec.start() } catch {}
    }
    track ? rec.start(track) : rec.start() // never rec.start(undefined): Chrome 157 throws a TypeError for that
  }

  // The voice has sent its whole question about a step: a spoken yes counts once that has finished playing (see said()).
  function armAsk(id) {
    if (speaking || queued || speechSynthesis.speaking || speechSynthesis.pending) askNext = id
    else { askHeard = id; askHeardAt = now() }
  }

  const state = {
    get live() { return live }, get muted() { return muted }, get speaking() { return speaking }, get hearing() { return hearing },
    get thinking() { return thinking }, get trackPath() { return trackPath }, get voice() { return voiceName },
    get armed() { return !speaking && now() - askHeardAt < ASK_FOR_MS ? askHeard : '' }, // the approval a spoken yes would answer now
  }
  return {
    state,
    on(type, fn) { (fns[type] ??= []).push(fn) },
    // Start or end the call. Ending stops listening and the voice; the server and the work carry on.
    async start(on) {
      live = on; ears++
      audio ??= host.audioContext(); audio.resume()
      muted = false
      if (live) await listen()
      else { rec?.stop(); hush(); stopEars(); hearing = false; trackPath = null; showSettings() }
      refresh()
    },
    // Muting turns off only the microphone: recognition stops and the track is released; the voice and the worker carry on.
    async mute(on) {
      muted = on
      if (muted) { ears++; rec?.abort(); stopEars(); hearing = false; tainted = false; mark('you', false); ghost('') }
      else await listen()
      refresh()
    },
    hush: () => hush(),
    typed(t) { audio ??= host.audioContext(); if (t) { hush(); turnState = ''; heard(t) } },
    set({ headphones: phones, voice } = {}) {
      if (phones !== undefined) headphones = !!phones
      if (voice) { voiceName = voice; audio ??= host.audioContext(); hush(); say('This is how I sound now.') }
    },
    // What the server says. Returns true when the voice starts waiting for the rest of your thought.
    server(e) {
      if (e.type === 'hello' || e.type === 'voices') {
        const names = e.type === 'hello' ? e.voices : e.names
        voices = names
        if (!names.includes(voiceName)) voiceName = names.includes('af_heart') ? 'af_heart' : names[0]
      } else if (e.type === 'say') {
        voiceText = voiceText == null ? e.text : `${voiceText} ${e.text}`
        turnText = voiceText
        say(e.text)
      } else if (e.type === 'turn_end') {
        voiceText = null; thinking = false; refresh(); if (e.ask) armAsk(e.ask)
      } else if (e.type === 'wait') {
        if (turnState !== 'sent' || nudged) return false // it has already said something, or was already told to answer
        turnState = 'waiting'; pendingAt = now(); thinking = false; refresh()
        console.info('[turn] held: the voice waits for the rest')
        tally({ kind: 'waited' })
        waitMore()
        return true
      } else if (e.type === 'asked') {
        if (askHeard === e.id) askHeard = ''; if (askNext === e.id) askNext = ''
      } else if (e.type === 'gone') thinking = false // the page lost the server, or found it again
      return false
    },
  }
}
