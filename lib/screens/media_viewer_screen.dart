import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:url_launcher/url_launcher.dart';
// لا نحتاج vector_math بشكل صريح لأن Matrix4 مدمج، ولكن للاحتياط
// import 'package:vector_math/vector_math_64.dart'; 

class MediaViewerScreen extends StatefulWidget {
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final String? senderName; // اسم المرسل (اختياري)

  const MediaViewerScreen({
    super.key,
    required this.mediaUrl,
    required this.mediaType,
    this.senderName,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> with SingleTickerProviderStateMixin {
  // Video Controllers
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  
  // Image Controllers
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  
  // State
  bool _isLoading = true;
  bool _showControls = true;
  bool _isDragging = false;
  double _dragOffset = 0.0;
  
  // Constants
  final double _minScale = 1.0;
  final double _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    
    // إخفاء شريط النظام لتجربة غامرة
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
      if (_animation != null) {
        _transformationController.value = _animation!.value;
      }
    });

    if (widget.mediaType == 'video') {
      _initializeVideoPlayer();
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.mediaUrl),
      );

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: true,
        aspectRatio: _videoPlayerController.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        placeholder: const Center(child: CircularProgressIndicator(color: Colors.white)),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.amber,
          handleColor: Colors.amber,
          backgroundColor: Colors.grey.withValues(alpha: 0.5),
          bufferedColor: Colors.white.withValues(alpha: 0.3),
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: Colors.amber,
          handleColor: Colors.amber,
          backgroundColor: Colors.grey.withValues(alpha: 0.5),
          bufferedColor: Colors.white.withValues(alpha: 0.3),
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error initializing video: $e");
      if (mounted) {
        setState(() {
          _isLoading = false; // Stop loading even on error
        });
      }
    }
  }

  @override
  void dispose() {
    // استعادة شريط النظام
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    if (widget.mediaType == 'video') {
      _videoPlayerController.dispose();
      _chewieController?.dispose();
    }
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // --- Logic: Double Tap Zoom ---
  void _handleDoubleTapDown(TapDownDetails details) {
    if (_transformationController.value != Matrix4.identity()) {
      _resetAnimation();
    } else {
      final position = details.localPosition;
      // تكبير نحو النقطة التي تم النقر عليها
      
      // إنشاء مصفوفة التحويل يدوياً لتجنب التحذيرات من translate/scale
      final Matrix4 translation = Matrix4.identity()
        ..setTranslationRaw(-position.dx * 2, -position.dy * 2, 0.0);
      
      final Matrix4 scaling = Matrix4.diagonal3Values(3.0, 3.0, 1.0);
      
      // الترتيب مهم: نطبق التحجيم ثم الإزاحة (أو العكس حسب المنطق، هنا نريد الإزاحة للنقطة ثم التكبير حولها تقريباً)
      // في الواقع، InteractiveViewer يتعامل مع المصفوفة.
      // لتبسيط الأمر: نريد مصفوفة تمثل التكبير 3x مع إزاحة بحيث تكون النقطة المضغوطة في المركز (تقريباً).
      // المصفوفة القديمة كانت: Identity .. translate .. scale
      
      final Matrix4 endMatrix = translation..multiply(scaling);

      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: endMatrix,
      ).animate(CurveTween(curve: Curves.easeOut).animate(_animationController));
      
      _animationController.forward(from: 0);
    }
  }

  void _resetAnimation() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurveTween(curve: Curves.easeOut).animate(_animationController));
    _animationController.forward(from: 0);
  }

  // --- Logic: Actions ---
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _downloadMedia() async {
    final Uri url = Uri.parse(widget.mediaUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الرابط')),
        );
      }
    }
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.mediaUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الرابط'), duration: Duration(seconds: 1)),
    );
  }

  // --- UI Builders ---
  Widget _buildImageViewer() {
    return GestureDetector(
      onTap: _toggleControls,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () {}, // مطلوب ليعمل DoubleTapDown بشكل صحيح
      child: InteractiveViewer(
        transformationController: _transformationController,
        panEnabled: true,
        minScale: _minScale,
        maxScale: _maxScale,
        onInteractionEnd: (details) {
          _resetAnimation(); // خيار: إعادة التعيين عند الانتهاء إذا أردت، أو اتركها كما هي
        },
        child: Hero(
          tag: widget.mediaUrl,
          child: Image.network(
            widget.mediaUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                  color: Colors.amber,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                    SizedBox(height: 16),
                    Text("تعذر تحميل الصورة", style: TextStyle(color: Colors.white54)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildVideoViewer() {
    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      return GestureDetector(
        onTap: _toggleControls, // Chewie يستولي على النقرات، لكن هذا قد يعمل في المساحات الفارغة
        child: SafeArea(
          child: Chewie(
            controller: _chewieController!,
          ),
        ),
      );
    } else {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 20),
            Text('جاري تحميل الفيديو...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
  }

  Widget _buildAppBar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: _showControls ? 0 : -100,
      left: 0,
      right: 0,
      child: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: widget.senderName != null 
            ? Text(widget.senderName!, style: const TextStyle(color: Colors.white, fontSize: 16)) 
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.link, color: Colors.white),
            onPressed: _copyLink,
            tooltip: "نسخ الرابط",
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white),
            onPressed: _downloadMedia,
            tooltip: "فتح في المتصفح",
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: _showControls ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Text(
               widget.mediaType == 'video' ? "فيديو" : "صورة",
               style: const TextStyle(color: Colors.white70, fontSize: 12),
             ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // حساب الشفافية بناءً على السحب
    final double opacity = max(0, 1 - (_dragOffset.abs() / 300));

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity), // خلفية تتلاشى عند السحب
      body: GestureDetector(
        // --- Swipe to Dismiss Logic ---
        onVerticalDragStart: (details) {
          setState(() => _isDragging = true);
        },
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffset += details.delta.dy;
            _showControls = false; // إخفاء الأدوات عند السحب
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset.abs() > 100) {
            // إذا سحب مسافة كافية، أغلق الشاشة
            Navigator.of(context).pop();
          } else {
            // إذا كانت السحبة قصيرة، أعد الصورة للمنتصف
            setState(() {
              _dragOffset = 0.0;
              _isDragging = false;
              _showControls = true;
            });
          }
        },
        child: Stack(
          children: [
            // المحتوى الرئيسي المتحرك
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.amber)
                    : (widget.mediaType == 'video')
                        ? _buildVideoViewer()
                        : _buildImageViewer(),
              ),
            ),

            // عناصر التحكم (تظهر وتختفي)
            if (!_isDragging) ...[
              _buildAppBar(),
              _buildBottomBar(),
            ],
          ],
        ),
      ),
    );
  }
}
