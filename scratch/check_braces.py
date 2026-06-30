def check_braces(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    stack = []
    
    for i, line in enumerate(lines):
        line_num = i + 1
        # Simple tokenization for braces
        for char in line:
            if char == '{':
                stack.append((line_num, line.strip()))
            elif char == '}':
                if stack:
                    start_line, content = stack.pop()
                    # Print pops around the end of HomeTabState (lines 740-1250)
                    if 740 <= line_num <= 1250 or 740 <= start_line <= 1250:
                        safe_content = content.encode('ascii', 'ignore').decode('ascii')
                        print(f"Pop: '{safe_content[:50]}' (from line {start_line}) closed at line {line_num}. Stack size: {len(stack)}")
                else:
                    print(f"Extra closing brace at line {line_num}")
                    
    print(f"Final stack size: {len(stack)}")
    if stack:
        print("Unclosed scopes:")
        for start_line, content in stack:
            if start_line > 500:
                safe_content = content.encode('ascii', 'ignore').decode('ascii')
                print(f"  Line {start_line}: {safe_content[:60]}")

check_braces(r"c:\xampp\htdocs\athelete\partner_app\lib\main.dart")
