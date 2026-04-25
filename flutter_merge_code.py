import os
from typing import List, Dict, Any

# ==========================================
# ⚙️ إعدادات السكربت (Flutter Smart AI Bundler Settings)
# ==========================================
OUTPUT_DIR = "Flutter_AI_Chunks"  # المجلد الذي سيتم إنشاء الملفات داخله
FILE_PREFIX = "Flutter_Part"  # بادئة اسم الملفات
SCRIPT_NAME = os.path.basename(__file__)

# 300,000 حرف تعادل تقريباً 75,000 Token، وهو رقم آمن جداً ومثالي للذكاء الاصطناعي.
MAX_CHARS_PER_CHUNK = 300000

MAX_FILE_SIZE_KB = 500  # الحد الأقصى لحجم الملف الواحد بالـ KB

# المجلدات الخاصة بفلاتر والتي يجب تجاهلها تماماً لتقليل التشويش وتوفير الـ Tokens
IGNORE_DIRS = {
    '.dart_tool', 'build', '.idea', '.vscode', '.git',
    'android', 'ios', 'windows', 'macos', 'linux', 'web', # تجاهل المنصات للتركيز على كود Dart
    'functions', # تم إضافة مجلد functions لتجاهله
    OUTPUT_DIR, 'assets', 'images', 'fonts'
}

# الامتدادات المسموح بجمعها لمشاريع فلاتر (تم التعديل للتركيز على كود Dart فقط)
ALLOWED_EXTENSIONS = {
    '.dart'
}

# الامتدادات والملفات المولدة تلقائياً والتي يجب تجاهلها
IGNORED_SUFFIXES = {
    '.g.dart', '.freezed.dart', '.part.dart'
}

def normalize_path(path: str) -> str:
    """توحيد شكل المسارات ليكون مفهوماً للذكاء الاصطناعي"""
    return path.replace("\\", "/").lstrip("./")

def get_markdown_language(filepath: str) -> str:
    """تحديد لغة البرمجة لتنسيقها بشكل صحيح بكتل Markdown"""
    ext = os.path.splitext(filepath)[1].lower()
    mapping = {
        '.dart': 'dart'
    }
    return mapping.get(ext, 'text')

def generate_project_tree(startpath: str) -> str:
    """بناء خريطة شجرية نظيفة لمشروع فلاتر لمساعدة الـ AI على فهم المعمارية"""
    tree_str = "📂 خريطة هيكل المشروع (Flutter Architecture):\n\n"

    root_basename = os.path.basename(os.path.abspath(startpath))
    tree_str += f"📁 {root_basename}/\n"

    for root, dirs, files in os.walk(startpath):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS and not d.startswith('.')]
        dirs.sort()

        level = root.replace(startpath, '').count(os.sep)
        indent = ' ' * 4 * level

        if root != startpath:
            folder_name = os.path.basename(root)
            tree_str += f"{indent}📁 {folder_name}/\n"

        subindent = ' ' * 4 * (level + 1)

        valid_files = [
            f for f in sorted(files)
            if f != SCRIPT_NAME
               and any(f.endswith(ext) for ext in ALLOWED_EXTENSIONS)
               and not any(f.endswith(suffix) for suffix in IGNORED_SUFFIXES)
        ]

        for f in valid_files:
            tree_str += f"{subindent}📄 {f}\n"

    return tree_str + "\n" + "=" * 80 + "\n\n"

def merge_project_files() -> None:
    """الوظيفة الرئيسية: مسح، تقسيم ذكي، وحفظ مشروع فلاتر كأجزاء مهيأة للـ AI"""
    print("🔍 جاري مسح وقراءة ملفات مشروع Flutter لتوزيعه بذكاء...")

    files_data: List[Dict[str, Any]] = []
    total_chars = 0
    total_lines = 0

    # ==========================================
    # 1. مرحلة المسح والقراءة (Scanning Phase)
    # ==========================================
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS and not d.startswith('.')]

        for file in sorted(files):
            # فلترة الامتدادات المطلوبة وتجاهل الملفات المولدة تلقائياً
            if (any(file.endswith(ext) for ext in ALLOWED_EXTENSIONS)
                    and not any(file.endswith(suffix) for suffix in IGNORED_SUFFIXES)
                    and file != SCRIPT_NAME):

                filepath = os.path.join(root, file)

                try:
                    if os.path.getsize(filepath) > MAX_FILE_SIZE_KB * 1024:
                        print(f"⚠️ تخطي: {normalize_path(filepath)} (حجمه يتجاوز {MAX_FILE_SIZE_KB}KB)")
                        continue
                except OSError:
                    continue

                content = ""
                try:
                    with open(filepath, "r", encoding="utf-8") as infile:
                        content = infile.read()
                except UnicodeDecodeError:
                    try:
                        with open(filepath, "r", encoding="utf-8-sig") as infile:
                            content = infile.read()
                    except Exception as err:
                        print(f"❌ تعذرت قراءة (ترميز غير مدعوم): {normalize_path(filepath)} - {err}")
                        continue
                except PermissionError:
                    print(f"❌ تعذرت قراءة (مرفوض الأذن): {normalize_path(filepath)}")
                    continue
                except Exception as err:
                    print(f"❌ خطأ غير متوقع في ملف: {normalize_path(filepath)} - {err}")
                    continue

                clean_path = normalize_path(filepath)
                files_data.append({
                    'path': clean_path,
                    'lang': get_markdown_language(clean_path),
                    'content': content,
                })
                total_chars += len(content)
                total_lines += len(content.splitlines())

    if not files_data:
        print("❌ لم يتم العثور على أي أكواد صالحة للنسخ! (تأكد من وضع السكربت في مجلد فلاتر الرئيسي)")
        return

    # ==========================================
    # 2. مرحلة التقسيم والتغليف (Dynamic Bundling Phase)
    # ==========================================
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    tree_str = generate_project_tree(".")

    chunks: List[Dict[str, Any]] = []
    current_content = tree_str
    current_files_list = ["Flutter_Architecture_Tree"]
    current_chars_count = len(tree_str)

    for f_data in files_data:
        file_wrapper = f"🔽🔽🔽 FILE START: {f_data['path']} 🔽🔽🔽\n"
        file_wrapper += f"```{f_data['lang']}\n"
        file_wrapper += f_data['content']
        if not f_data['content'].endswith('\n'):
            file_wrapper += '\n'
        file_wrapper += "```\n"
        file_wrapper += f"🔼🔼🔼 FILE END: {f_data['path']} 🔼🔼🔼\n\n\n"

        wrapper_len = len(file_wrapper)

        if current_chars_count + wrapper_len > MAX_CHARS_PER_CHUNK and len(current_files_list) > 0:
            chunks.append({
                "files_list": current_files_list.copy(),
                "content": current_content
            })
            current_content = ""
            current_files_list = []
            current_chars_count = 0

        current_content += file_wrapper
        current_files_list.append(f_data['path'])
        current_chars_count += wrapper_len

    if current_content:
        chunks.append({
            "files_list": current_files_list.copy(),
            "content": current_content
        })

    # ==========================================
    # 3. مرحلة الكتابة على القرص (Writing Phase)
    # ==========================================
    actual_parts = len(chunks)

    for f in os.listdir(OUTPUT_DIR):
        if f.startswith(FILE_PREFIX) and f.endswith(".txt"):
            try:
                os.remove(os.path.join(OUTPUT_DIR, f))
            except OSError:
                pass

    for index, chunk in enumerate(chunks):
        part_num = index + 1
        filename = os.path.join(OUTPUT_DIR, f"{FILE_PREFIX}_{part_num}.txt")

        with open(filename, "w", encoding="utf-8") as outfile:
            outfile.write(f"🤖 هذا الملف (الجزء {part_num} من {actual_parts}) هو جزء من مشروع Flutter موجه لك.\n")
            outfile.write("⚠️ تعليمات هامة: لا تقم بكتابة أي كود أو إجابة حتى أقوم برفع جميع الأجزاء لك.\n")
            if part_num == actual_parts:
                outfile.write("✅ هذا هو الجزء الأخير. الكود الآن مكتمل في ذاكرتك، انتظر أوامري ومراجعتي.\n")

            outfile.write("\n📑 الملفات المضمنة في هذا الجزء:\n")
            for pf in chunk['files_list']:
                outfile.write(f"  - {pf}\n")
            outfile.write("=" * 80 + "\n\n")

            outfile.write(chunk['content'])

    # ==========================================
    # 4. ملخص العملية (Summary)
    # ==========================================
    print(f"\n✅ اكتملت التعبئة بنجاح!")
    print(f"📦 إجمالي ملفات فلاتر المقروءة : {len(files_data)} ملفاً.")
    print(f"📝 إجمالي الأسطر البرمجية       : {total_lines:,} سطر.")
    print(f"⚖️ إجمالي حجم الكود             : {total_chars:,} حرف.")
    print(f"📂 تم إنشاء المجلد '{OUTPUT_DIR}' وبداخله ({actual_parts}) أجزاء جاهزة للـ AI.")

if __name__ == "__main__":
    merge_project_files()