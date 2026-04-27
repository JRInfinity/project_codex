import os

input_dir = r"C:\Users\huawei\Desktop\project_codex\rtl"
output_dir = r"C:\Users\huawei\Desktop\project_codex\svtxt"

os.makedirs(output_dir, exist_ok=True)

for root, dirs, files in os.walk(input_dir):
    # 🚫 跳过 sim 文件夹
    if "sim" in root.lower():
        continue

    for file in files:
        if file.endswith(".sv"):
            sv_path = os.path.join(root, file)

            # 👉 防止重名（加路径前缀）
            relative_path = os.path.relpath(sv_path, input_dir)
            safe_name = relative_path.replace("\\", "_").replace("/", "_")
            txt_name = safe_name.replace(".sv", ".txt")

            txt_path = os.path.join(output_dir, txt_name)

            with open(sv_path, "r", encoding="utf-8", errors="ignore") as f_in:
                content = f_in.read()

            with open(txt_path, "w", encoding="utf-8") as f_out:
                f_out.write(content)

            print(f"✔ {sv_path} -> {txt_path}")

print("🎉 全部转换完成！")