import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';

enum RecordingState {
  uninitialized,
  stopped,
  recording,
  playing,
  paused,
}

class AudioRecorderService with ChangeNotifier {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  StreamSubscription? _recorderSubscription;

  RecordingState _recordingState = RecordingState.uninitialized;
  RecordingState get recordingState => _recordingState;

  String? _recordedFilePath;
  String? get recordedFilePath => _recordedFilePath;

  Stream<PlaybackDisposition>? get onProgress => _player?.onProgress;

  // تخزين بيانات الموجات الصوتية (Normalized 0.0 - 1.0)
  final List<double> _waveformData = [];
  List<double> get waveformData => List.unmodifiable(_waveformData);

  // Stream للحصول على تحديثات الموجة أثناء التسجيل (للعرض المباشر إذا لزم الأمر)
  final StreamController<double> _amplitudeStreamController = StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeStreamController.stream;

  bool get isRecorderInitialized => _recorder != null;
  bool get isPlayerInitialized => _player != null;

  AudioRecorderService() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  Future<void> init() async {
    try {
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw RecordingPermissionException('Microphone permission not granted');
      }

      await _recorder!.openRecorder();
      await _player!.openPlayer();

      await _player!.setSubscriptionDuration(const Duration(milliseconds: 50));
      await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 50)); // زيادة التحديث لجعل الموجة أكثر سلاسة

      // تحسين إعدادات الجلسة الصوتية للتشغيل والتسجيل
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.defaultToSpeaker | // إجبار الصوت على الخروج من مكبر الصوت
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowAirPlay,
        avAudioSessionMode: AVAudioSessionMode.voiceChat, // تغيير الوضع إلى VoiceChat للحصول على جودة أفضل للمحادثات
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication, // استخدام voiceCommunication
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      _recordingState = RecordingState.stopped;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing recorder: $e');
    }
  }

  Future<void> startRecording() async {
    if (_recorder == null) return;
    try {
      if (_player!.isPlaying) {
        await stopPlaying();
      }

      // التأكد من إعداد الجلسة قبل التسجيل مباشرة
      final session = await AudioSession.instance;
      await session.setActive(true);

      final Directory tempDir = await getTemporaryDirectory();
      final String path = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';

      _waveformData.clear(); 

      await _recorder!.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
        audioSource: AudioSource.microphone, // التأكد من استخدام الميكروفون الأساسي
      );

      _recorderSubscription = _recorder!.onProgress!.listen((e) {
        double decibels = e.decibels ?? 0.0;
        
        // تحسين معادلة الموجات للتعامل مع القيم السالبة والموجبة بشكل أفضل
        double normalized = 0.0;
        
        // تحسين الحساسية: بعض الأجهزة تعطي قيماً منخفضة جداً
        // سنستخدم نطاق ديناميكي أوسع
        
        if (decibels > 0) {
           normalized = (decibels / 100.0);
        } else {
           // المجال المتوقع: -80 ديسيبل (صمت) إلى 0 ديسيبل (أعلى صوت)
           const minDb = -80.0;
           if (decibels < minDb) {
             normalized = 0.0;
           } else {
             // تحويل لوغاريتمي ليعكس إدراك الأذن للصوت بشكل أفضل
             // يجعل التغيرات في الصوت المنخفض أكثر وضوحاً
             double ratio = (decibels - minDb) / (0 - minDb);
             normalized = math.pow(ratio, 0.8).toDouble(); // أس أقل من 1 لزيادة القيم المنخفضة
           }
        }
        
        // إضافة بعض "التضخيم" للقيم الصغيرة لتظهر بشكل أوضح
        normalized = normalized.clamp(0.0, 1.0);
        
        // تقليل "الضجيج" الصامت جداً
        if (normalized < 0.05) normalized = 0.02; // حافظ على حد أدنى بسيط جداً للحركة

        // تنعيم الحركة (Smoothing)
        if (_waveformData.isNotEmpty) {
           double lastValue = _waveformData.last;
           // نأخذ متوسط مرجح بين القيمة الحالية والسابقة لتنعيم الانتقال
           normalized = (lastValue * 0.6) + (normalized * 0.4); 
        }

        _waveformData.add(normalized);
        _amplitudeStreamController.add(normalized);
        notifyListeners();
      });

      _recordedFilePath = path;
      _recordingState = RecordingState.recording;
      notifyListeners();
    } catch (e) {
      debugPrint("Error starting recorder: $e");
      cancelRecording();
    }
  }

  Future<void> stopRecording() async {
    if (_recorder == null) return;
    try {
      await _recorder!.stopRecorder();
      _recorderSubscription?.cancel();
      _recorderSubscription = null;
      
      _recordingState = RecordingState.stopped;
      notifyListeners();
    } catch (e) {
      debugPrint("Error stopping recorder: $e");
    }
  }

  Future<void> cancelRecording() async {
    try {
      if (_recorder != null && _recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }
      _recorderSubscription?.cancel();
      _recorderSubscription = null;
      _waveformData.clear();

      if (_recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint("Error canceling: $e");
    } finally {
      _recordedFilePath = null;
      _recordingState = RecordingState.stopped;
      notifyListeners();
    }
  }

  Future<void> startPlaying({String? filePath}) async {
    final path = filePath ?? _recordedFilePath;
    if (path == null || _player == null) return;

    try {
      if (_recorder!.isRecording) {
        await stopRecording();
      }

      if (_player!.isPlaying) {
        await _player!.stopPlayer();
      }

      // إعادة تهيئة الجلسة للتأكد من توجيه الصوت للسماعة الخارجية
      // في بعض الأحيان عند التبديل بين التسجيل والتشغيل قد تتغير الإعدادات
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.defaultToSpeaker |
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowAirPlay,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication, 
        ),
      ));
      await session.setActive(true);

      _recordingState = RecordingState.playing;
      notifyListeners();

      await _player!.startPlayer(
        fromURI: path,
        codec: Codec.aacADTS,
        whenFinished: () {
          _recordingState = RecordingState.stopped;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint("Error playing audio: $e");
      stopPlaying();
    }
  }

  Future<void> stopPlaying() async {
    if (_player == null) return;
    try {
      await _player!.stopPlayer();
    } catch (e) {
      // ignore
    } finally {
      _recordingState = RecordingState.stopped;
      notifyListeners();
    }
  }

  Future<void> pausePlaying() async {
    if (_player == null) return;
    try {
      await _player!.pausePlayer();
      _recordingState = RecordingState.paused;
      notifyListeners();
    } catch (e) {
      debugPrint("Error pausing: $e");
    }
  }

  Future<void> resumePlaying() async {
    if (_player == null) return;
    try {
      await _player!.resumePlayer();
      _recordingState = RecordingState.playing;
      notifyListeners();
    } catch (e) {
      debugPrint("Error resuming: $e");
    }
  }

  Future<void> seekToPlayer(int milliSecs) async {
    if (_player != null && (_player!.isPlaying || _player!.isPaused)) {
      await _player!.seekToPlayer(Duration(milliseconds: milliSecs));
    }
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _recorder?.closeRecorder();
    _player?.closePlayer();
    _amplitudeStreamController.close();
    super.dispose();
  }
}
