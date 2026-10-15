-- §1c: tricky string literals (escaped quotes, single-quoted with embedded
-- double quotes, long-bracket strings, backslashes) must survive every pass.
print("a\"b")
print('he said "hi"')
print([[long "quoted" text]])
print("back\\slash")
print('mixed \'quotes\' and "dquotes"')
