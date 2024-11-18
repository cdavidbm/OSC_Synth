s.quit;
OSCdef.freeAll;

s.boot;                  // Iniciar servidor
NetAddr.localAddr.port;  // Ver puerto actual
thisProcess.openPorts;   // Ver puertos abiertos
s.serverRunning;         // Estado del servidor
OSCFunc.trace(false);     // Activar el debugging de OSC si es necesario
OSCdef.all;              // Ver todos los OSCdefs activos


// Sistema completo de SuperCollider con OSC
(
// 0. Configuración inicial y debugging
s.quit;

// Configurar el servidor
s.options.numBuffers = 1024 * 16;
s.options.memSize = 8192 * 16;
s.options.maxNodes = 1024 * 32;
s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 2;


// Variables globales para el sistema OSC
~lastOSCTime = 0;
~isPlaying = false;
~timeoutThreshold = 1;
~oscInput = [0.5, 0.5];

// Iniciar el servidor
s.waitForBoot({
    "Servidor iniciado correctamente".postln;
    s.meter;
    s.volume.volume = 0;

    // 1. Cargar buffers
    ~folder1 = "/Users/christiandavid/sc/d2/src1";
    ~folder2 = "/Users/christiandavid/sc/d2/src2";

    // Verificar carpetas
    if(File.exists(~folder1).not) { "¡ADVERTENCIA: La carpeta 1 no existe!".postln; };
    if(File.exists(~folder2).not) { "¡ADVERTENCIA: La carpeta 2 no existe!".postln; };

    // Cargar buffers
    ~buffers1 = PathName(~folder1).entries.collect { |path|
        var buf = Buffer.read(s, path.fullPath);
        "Cargando buffer: %\n".format(path.fileName).post;
        buf
    };

    ~buffers2 = PathName(~folder2).entries.collect { |path|
        var buf = Buffer.read(s, path.fullPath);
        "Cargando buffer: %\n".format(path.fileName).post;
        buf
    };

    "Número de buffers cargados en folder1: %\n".format(~buffers1.size).post;
    "Número de buffers cargados en folder2: %\n".format(~buffers2.size).post;

    // 2. Sistema de monitoreo OSC mejorado
    ~checkTimeout = {
        if(~isPlaying && (Main.elapsedTime - ~lastOSCTime > ~timeoutThreshold)) {
            "No se recibieron datos OSC por % segundos - deteniendo reproducción".format(~timeoutThreshold).postln;
            ~stopAll.value;
            ~isPlaying = false;
        };
    };

    // Definir receptor OSC con monitoreo
    OSCdef(\receiveInputs, { |msg, time, addr, port|
        var normalizedInputs;

        // Actualizar timestamp
        ~lastOSCTime = Main.elapsedTime;

        // Normalizar valores de [-1,1] a [0,1]
        normalizedInputs = msg[1..].collect({ |val|
            val.linlin(-1, 1, 0, 1)
        });

        // Actualizar valores OSC
        ~oscInput = normalizedInputs;

        // Iniciar reproducción si no está activa
        if(~isPlaying.not) {
            "Reiniciando reproducción".postln;
            ~startAll.value;
            ~isPlaying = true;
        };

        // Debug
        "OSC recibido: %".format(normalizedInputs).postln;

        // Actualizar el patrón
        ~updatePattern.value;
    }, '/inputs');

    // Rutina para verificar timeouts
    ~timeoutRoutine = Routine({
        loop {
            ~checkTimeout.value;
            0.5.wait;
        };
    }).play;

    // 3. SynthDef
    SynthDef(\bufferPlayerExtended, {
        |buf, amp = 0.5, pan = 0, revMix = 0.2,
        delayTime = 0.5, feedback = 0.3, out = 0,
        fadeIn = 0.1, fadeOut = 0.1, gate = 1,
        playRate = 1.0, reverse = 0,
        distAmt = 0.0, noiseAmt = 0.0,
        lpfFreq = 20000, hpfFreq = 20,
        pitchShift = 1.0, timeStretch = 1.0,
        wobbleRate = 0.5, wobbleDepth = 0.0,
        ringModFreq = 0, ringModAmt = 0,
        crushAmt = 0|

        var sig, delayed, env, noise, direction, crushedSig;

        direction = (1 - reverse * 2);

        env = EnvGen.kr(
            Env.asr(fadeIn, 1, fadeOut),
            gate,
            doneAction: 2
        );

        sig = PlayBuf.ar(2, buf,
            BufRateScale.kr(buf) * playRate * direction *
            (1 + (SinOsc.kr(wobbleRate) * wobbleDepth)),
            doneAction: 0
        );

        sig = PitchShift.ar(sig,
            windowSize: 0.2,
            pitchRatio: pitchShift,
            pitchDispersion: 0.0,
            timeDispersion: timeStretch
        );

        noise = PinkNoise.ar(noiseAmt) + WhiteNoise.ar(noiseAmt * 0.5);
        sig = (sig * (1 - noiseAmt)) + noise;

        sig = (sig * (1 + distAmt)).tanh;

        crushedSig = sig.round(2.pow(crushAmt.neg));
        sig = SelectX.ar(crushAmt, [sig, crushedSig]);

        sig = sig * (1 - ringModAmt + (ringModAmt * SinOsc.ar(ringModFreq)));

        sig = RLPF.ar(sig, lpfFreq, 0.707);
        sig = RHPF.ar(sig, hpfFreq, 0.707);

        sig = sig * env;
        sig = Pan2.ar(sig, pan, amp);

        sig = FreeVerb.ar(sig,
            mix: revMix.clip(0, 1),
            room: 0.6,
            damp: 0.5
        );

        delayed = DelayL.ar(sig, 2,
            delayTime.clip(0, 2) * (1 + (SinOsc.kr(0.1) * 0.01))
        ) * feedback.clip(0, 0.95);

        sig = sig + delayed;

        sig = Compander.ar(sig, sig,
            thresh: 0.5,
            slopeBelow: 1,
            slopeAbove: 0.5,
            clampTime: 0.01,
            relaxTime: 0.01
        );
        sig = Limiter.ar(sig, 0.95);

        Out.ar(out, sig);
    }).add;

    // 4. Patrón principal
    Pdef(\pattern, Pbind(
        \instrument, \bufferPlayerExtended,
        \buf, Pfunc({ |ev|
            var bufSelect = ~oscInput[0].linlin(0, 1, 0, ~buffers1.size-1).floor;
            ~buffers1[bufSelect].bufnum;
        }),

        \amp, Pfunc({ ~oscInput[0].linlin(0, 1, 0.2, 0.7) }),
        \pan, Pfunc({ ~oscInput[1].linlin(0, 1, -1, 1) }),

        \revMix, Pfunc({ ~oscInput[1].linlin(0, 1, 0.1, 0.8) }),
        \delayTime, Pfunc({ ~oscInput[0].linlin(0, 1, 0.3, 1.5) }),
        \feedback, Pfunc({ ~oscInput[1].linlin(0, 1, 0.2, 0.7) }),

        \fadeIn, 2,
        \fadeOut, 2,

        \playRate, Pfunc({
            var rates = [0.5, 1, 1.5, 2];
            var index = (~oscInput[0] * rates.size).floor;
            rates[index];
        }),
        \reverse, Pfunc({
            if(~oscInput[1] > 0.7) { 1 } { 0 }
        }),
        \distAmt, Pfunc({ ~oscInput[0].linlin(0, 1, 0, 0.7) }),
        \noiseAmt, Pfunc({ ~oscInput[1].linlin(0, 1, 0, 0.2) }),
        \crushAmt, Pfunc({ ~oscInput[0].linlin(0, 1, 0, 0.8) }),
        \lpfFreq, Pfunc({ ~oscInput[1].linexp(0, 1, 200, 20000) }),
        \hpfFreq, Pfunc({ ~oscInput[0].linexp(0, 1, 20, 1000) }),
        \pitchShift, Pfunc({
            var shifts = [0.5, 1, 1.5, 2];
            var index = (~oscInput[1] * shifts.size).floor;
            shifts[index];
        }),
        \timeStretch, Pfunc({ ~oscInput[0].linlin(0, 1, 0.8, 1.2) }),
        \wobbleRate, Pfunc({ ~oscInput[1].linlin(0, 1, 0.1, 2.0) }),
        \wobbleDepth, Pfunc({ ~oscInput[0].linlin(0, 1, 0, 0.3) }),
        \ringModFreq, Pfunc({ ~oscInput[1].linexp(0, 1, 0.1, 1000) }),
        \ringModAmt, Pfunc({ ~oscInput[0].linlin(0, 1, 0, 0.8) }),

        \dur, Pfunc({
            var durs = [1, 2, 4];
            var index = (~oscInput[0] * durs.size).floor;
            durs[index];
        })
    ));

    // 5. Función de actualización
    ~updatePattern = {
        "Actualizando patrón con valores OSC: %\n".format(~oscInput).post;
        Pdef(\pattern).quant = 0;
    };

    // 6. Rutina de actualización
    ~routine = Routine({
        loop {
            ~updatePattern.value;
            0.1.wait;
        }
    });

    // 7. Funciones de control
    ~startAll = {
        if(~buffers1.isEmpty) {
            "¡No hay buffers para reproducir!".postln;
        } {
            "Iniciando reproducción...".postln;
            "Estado OSC: %\n".format(~oscInput).post;
            "Buffers disponibles: %\n".format(~buffers1.size).post;

            Pdef(\pattern).play;
            ~routine.reset.play;
        };
    };

    ~stopAll = {
        "Deteniendo reproducción...".postln;
        Pdef(\pattern).stop;
        ~routine.stop;
    };

    // Test inicial de audio
    {
        SinOsc.ar(440, 0, 0.1) ! 2 * Line.kr(1, 0, 1, doneAction: 2)
    }.play;

    "Inicialización completa.".postln;
    "Sistema esperando datos OSC...".postln;
    "El sistema iniciará automáticamente al recibir datos OSC".postln;
    "y se detendrá después de % segundos sin datos.".format(~timeoutThreshold).postln;
});
)


// Para limpiar todo
~cleanup = {
    ~stopAll.value;
    ~timeoutRoutine.stop;
    OSCdef(\receiveInputs).free;
    ~buffers1.do(_.free);
    ~buffers2.do(_.free);
    "Sistema limpiado.".postln;
};