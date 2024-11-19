// Comandos de inicio y verificación
s.quit;
OSCdef.freeAll;

s.boot;                  // Iniciar servidor
NetAddr.localAddr.port;  // Ver puerto actual
thisProcess.openPorts;   // Ver puertos abiertos
s.addr;                  // Ver información del servidor
s.serverRunning;        // Estado del servidor
OSCFunc.trace(false);    // Activar el debugging de OSC
OSCdef.all;             // Ver todos los OSCdefs activos

// Sistema completo de SuperCollider con OSC y dos buffers
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
//    s.meter;
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
        "Cargando buffer 1: %\n".format(path.fileName).post;
        buf
    };

    ~buffers2 = PathName(~folder2).entries.collect { |path|
        var buf = Buffer.read(s, path.fullPath);
        "Cargando buffer 2: %\n".format(path.fileName).post;
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

    // Configuración del receptor OSC
    thisProcess.openUDPPort(57120); // Abre explícitamente el puerto 57120

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

    // 3. SynthDef modificado para dos buffers
	// SynthDef modificado (mantiene los parámetros pero no aplica los efectos directamente)
	SynthDef(\bufferPlayerExtended, {
		|buf1, buf2, mixRatio = 0.5, amp = 0.5, pan = 0,
		revMix = 0.2, delayTime = 0.5, feedback = 0.3, out = 0,
		fadeIn = 0.1, fadeOut = 0.1, gate = 1,
		playRate = 1.0, reverse = 0,
		distAmt = 0.0, noiseAmt = 0.0,
		lpfFreq = 20000, hpfFreq = 20,
		pitchShift = 1.0, timeStretch = 1.0,
		wobbleRate = 0.5, wobbleDepth = 0.0,
		ringModFreq = 0, ringModAmt = 0,
		crushAmt = 0,
		// Parámetros de control de efectos
		effectWobble = 0,
		effectPitch = 0,
		effectNoise = 0,
		effectDist = 0,
		effectCrush = 0,
		effectRing = 0,
		effectFilter = 0,
		effectReverb = 0,
		// Parámetros para el efecto binaural
		binauralBaseFreq = 440, // frecuencia base
		binauralDiff = 4.0,     // diferencia entre oídos
		binauralAmp = 0.1|      // amplitud del efecto binaural

		var sig1, sig2, sig, delayed, env, noise, direction, crushedSig;
		var binauralL, binauralR, binauralSig;

		direction = (1 - reverse * 2);
		env = EnvGen.kr(Env.asr(fadeIn, 1, fadeOut), gate, doneAction: 2);

		// Efecto binaural - diferente frecuencia para cada oído
		binauralL = SinOsc.ar(binauralBaseFreq) * binauralAmp;
		binauralR = SinOsc.ar(binauralBaseFreq + binauralDiff) * binauralAmp;
		binauralSig = [binauralL, binauralR];

		// Reproducción normal de buffers
		sig1 = PlayBuf.ar(2, buf1,
			BufRateScale.kr(buf1) * playRate * direction *
			(1 + (SinOsc.kr(wobbleRate) * wobbleDepth * effectWobble)),
			doneAction: 0
		);

		sig2 = PlayBuf.ar(2, buf2,
			BufRateScale.kr(buf2) * playRate * direction *
			(1 + (SinOsc.kr(wobbleRate) * wobbleDepth * effectWobble)),
			doneAction: 0
		);

		// Mezclar la señal binaural solo cuando buf1 está activo
		sig1 = sig1 + binauralSig;

		sig = XFade2.ar(sig1, sig2, mixRatio * 2 - 1);

		// Pitch shift
		sig = Select.ar(effectPitch, [
			sig,
			PitchShift.ar(sig, 0.2, pitchShift, 0.0, timeStretch)
		]);

		// Noise
		noise = PinkNoise.ar(noiseAmt) + WhiteNoise.ar(noiseAmt * 0.5);
		sig = Select.ar(effectNoise, [
			sig,
			(sig * (1 - noiseAmt)) + noise
		]);

		// Distortion
		sig = Select.ar(effectDist, [
			sig,
			(sig * (1 + distAmt)).tanh
		]);

		// Bit crushing
		crushedSig = sig.round(2.pow(crushAmt.neg));
		sig = Select.ar(effectCrush, [
			sig,
			SelectX.ar(crushAmt, [sig, crushedSig])
		]);

		// Ring modulation
		sig = Select.ar(effectRing, [
			sig,
			sig * (1 - ringModAmt + (ringModAmt * SinOsc.ar(ringModFreq)))
		]);

		// Filters
		sig = Select.ar(effectFilter, [
			sig,
			RHPF.ar(RLPF.ar(sig, lpfFreq, 0.707), hpfFreq, 0.707)
		]);

		sig = sig * env;
		sig = Pan2.ar(sig, pan, amp);

		// Reverb and delay
		delayed = DelayL.ar(sig, 2, delayTime.clip(0, 2) * (1 + (SinOsc.kr(0.1) * 0.01))) * feedback.clip(0, 0.95);
		sig = Select.ar(effectReverb, [
			sig,
			FreeVerb.ar(sig + delayed, revMix.clip(0, 1), 0.6, 0.5)
		]);

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

	// Pdef actualizado para incluir los parámetros binaurales
	Pdef(\pattern, Pbind(
		\instrument, \bufferPlayerExtended,
		\buf1, Pfunc({ |ev|
			var bufSelect = ~oscInput[0].linlin(0, 1, 0, ~buffers1.size-1).floor;
			~buffers1[bufSelect].bufnum;
		}),
		\buf2, Pfunc({ |ev|
			var bufSelect = ~oscInput[0].linlin(0, 1, 0, ~buffers2.size-1).floor;
			~buffers2[bufSelect].bufnum;
		}),
		\mixRatio, Pfunc({ ~oscInput[1] }),

		// Parámetros binaurales
		\binauralBaseFreq, Pfunc({
			// Frecuencias base comunes para efectos binaurales
			var freqs = [432, 440, 444, 528];
			freqs.choose;
		}),
		\binauralDiff, Pfunc({
			// Diferencias típicas para efectos binaurales (1-10 Hz)
			rrand(1.0, 10.0);
		}),
		\binauralAmp, 0.1, // Amplitud fija pero ajustable

		// Parámetros base
		\amp, Pfunc({ ~oscInput[0].linlin(0, 1, 0.2, 0.7) }),
		\pan, Pfunc({ ~oscInput[1].linlin(0, 1, -1, 1) }),

		// Activación aleatoria de efectos
		\effectWobble, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectPitch, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectNoise, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectDist, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectCrush, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectRing, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectFilter, Pfunc({ if(0.3.coin) { 1 } { 0 } }),
		\effectReverb, Pfunc({ if(0.3.coin) { 1 } { 0 } }),

		// Resto de parámetros...
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
        if(~buffers1.isEmpty || ~buffers2.isEmpty) {
            "¡No hay suficientes buffers para reproducir!".postln;
        } {
            "Iniciando reproducción...".postln;
            "Estado OSC: %\n".format(~oscInput).post;
            "Buffers disponibles - Grupo 1: %, Grupo 2: %\n".format(
                ~buffers1.size, ~buffers2.size
            ).post;

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
//    {
//        SinOsc.ar(440, 0, 0.1) ! 2 * Line.kr(1, 0, 1, doneAction: 2)
//    }.play;

    "Inicialización completa.".postln;
    "Sistema esperando datos OSC...".postln;
    "El sistema iniciará automáticamente al recibir datos OSC".postln;
    "y se detendrá después de % segundos sin datos.".format(~timeoutThreshold).postln;
    "Control de mezcla: OSC[1] controla la mezcla entre los dos buffers".postln;
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