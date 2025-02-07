import os

rpt_files = [
    os.path.join("./build/report", f)
    for f in os.listdir("./build/report")
    if os.path.isfile(os.path.join("./build/report", f)) and f.endswith(".rpt")
]

with open(os.environ["GITHUB_STEP_SUMMARY"], "w") as f:
    f.write(f"# STA Report\n\n")

for rpt_file in rpt_files:
    with open(rpt_file) as f:
        lines = f.readlines()
        table_head, table_split = None, None
        for idx, line in enumerate(lines):
            if "+" in line:
                if table_head is None:
                    table_head = idx
                elif table_split is None:
                    table_split = idx
                else:
                    table = "".join(lines[table_head + 1 : idx])
                    table = (
                        table.replace("+", "|")
                        .replace("_", "\\_")
                        .replace("*", "\\*")
                        .replace("~", "\\~")
                        .replace("`", "\\`")
                        .replace("#", "\\#")
                    )
                    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
                        f.write(f"## {rpt_file.split('/')[-1][:-4]}\n\n")
                        f.write(f"> {lines[0].strip()}\n\n")
                        f.write(table)
                    break

with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
    f.write(f"\n---\nEnd of Summary\n")
