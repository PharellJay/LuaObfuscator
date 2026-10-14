// Ordered module manifest. Mirrors Libraries.lua's require order, then Main.
// Libraries.lua itself is intentionally omitted: it only issues `require`s, and
// the worker loads every file directly in this order, so a no-op `require` is
// safe. Dotted names map to paths: "vm.Compiler" -> "vm/Compiler.lua".
// This is the ONE place to update if a module is added to the pipeline.
self.OBFUSCATOR_MODULES = [
  "Utils", "Config", "Reader", "CommentRemover", "Lexer", "Parser",
  "ExprAST", "Emitter",
  "vm.Opcodes", "vm.Compiler", "vm.Interp", "vm.Serializer", "vm.Virtualize",
  "ControlFlowFlattening", "DeadCodeInjector", "VariableRenamer",
  "NumericalObfuscator", "LexicalObfuscator", "StringSplitter",
  "ConstantPooling", "Minify",
  "Main",
];
