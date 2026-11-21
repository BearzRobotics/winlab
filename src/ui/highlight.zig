//! Small syntax highlighter for the shells the course teaches (PowerShell, bash, cmd).
//! It only splits text into coloured runs; it never changes or drops a byte, so every token slice
//! concatenated gives back the input. Not a parser: it is a lexer good enough to colour examples.
const std = @import("std");

pub const Kind = enum { plain, comment, string, variable, keyword, command, param, number };
pub const Lang = enum { powershell, bash, cmd, generic };

pub const Token = struct { kind: Kind, text: []const u8 };

/// The language of a fenced block: its info string, else a guess from the text.
pub fn langFor(info: []const u8, text: []const u8) Lang {
    var tag = info;
    if (std.mem.indexOfAny(u8, tag, " \t{")) |i| tag = tag[0..i];
    const eq = std.ascii.eqlIgnoreCase;
    if (eq(tag, "powershell") or eq(tag, "pwsh") or eq(tag, "ps1") or eq(tag, "ps")) return .powershell;
    if (eq(tag, "bash") or eq(tag, "sh") or eq(tag, "shell") or eq(tag, "zsh")) return .bash;
    if (eq(tag, "cmd") or eq(tag, "bat") or eq(tag, "batch") or eq(tag, "dos")) return .cmd;
    if (tag.len > 0) return .generic;
    // No tag: look for the shell's own giveaways.
    if (std.mem.indexOf(u8, text, "PS ") != null and std.mem.indexOf(u8, text, "PS >") == null and std.mem.startsWith(u8, text, "PS ")) return .powershell;
    var it = std.mem.tokenizeAny(u8, text, " \t\r\n|(){};=,\"'");
    while (it.next()) |w| {
        if (isCmdlet(w)) return .powershell;
        if (w.len > 1 and w[0] == '$' and std.ascii.isAlphabetic(w[1])) return .powershell;
    }
    if (std.mem.indexOf(u8, text, "%") != null and (std.mem.indexOf(u8, text, "%~") != null or hasPercentVar(text))) return .cmd;
    if (std.mem.startsWith(u8, text, "C:\\") or std.mem.startsWith(u8, text, ">")) return .cmd;
    if (std.mem.startsWith(u8, text, "$ ") or std.mem.startsWith(u8, text, "#!/")) return .bash;
    return .generic;
}

fn hasPercentVar(text: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, i, '%')) |s| {
        const e = std.mem.indexOfScalarPos(u8, text, s + 1, '%') orelse return false;
        if (e > s + 1 and e - s < 40 and std.mem.indexOfAny(u8, text[s + 1 .. e], " \t\n") == null) return true;
        i = e + 1;
    }
    return false;
}

/// Verb-Noun with an upper-case start, like `Get-Service`.
fn isCmdlet(w: []const u8) bool {
    const dash = std.mem.indexOfScalar(u8, w, '-') orelse return false;
    if (dash == 0 or dash + 1 >= w.len or !std.ascii.isUpper(w[0]) or !std.ascii.isUpper(w[dash + 1])) return false;
    for (w) |c| if (!std.ascii.isAlphanumeric(c) and c != '-') return false;
    return true;
}

const ps_keywords = [_][]const u8{ "if", "else", "elseif", "foreach", "for", "while", "do", "until", "switch", "function", "filter", "param", "return", "try", "catch", "finally", "throw", "break", "continue", "in", "begin", "process", "end", "exit", "trap", "class", "enum" };
const bash_keywords = [_][]const u8{ "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "function", "in", "return", "select", "break", "continue", "exit", "local", "export", "set", "unset", "source", "alias", "time" };
const cmd_keywords = [_][]const u8{ "if", "else", "for", "in", "do", "goto", "call", "echo", "set", "exit", "not", "exist", "defined", "errorlevel", "setlocal", "endlocal", "shift", "pause", "title", "cls", "equ", "neq", "lss", "leq", "gtr", "geq" };

fn inList(list: []const []const u8, w: []const u8, ci: bool) bool {
    for (list) |k| {
        if (if (ci) std.ascii.eqlIgnoreCase(k, w) else std.mem.eql(u8, k, w)) return true;
    }
    return false;
}

pub const Lexer = struct {
    src: []const u8,
    lang: Lang,
    pos: usize = 0,
    /// Only blanks since the last newline.
    line_start: bool = true,

    pub fn init(src: []const u8, lang: Lang) Lexer {
        return .{ .src = src, .lang = lang };
    }

    fn isWordStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn isWordChar(self: *const Lexer, c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_' or (self.lang == .powershell and c == '-') or c == '.';
    }

    fn take(self: *Lexer, n: usize, kind: Kind) Token {
        const t: Token = .{ .kind = kind, .text = self.src[self.pos..][0..n] };
        self.pos += n;
        self.line_start = false;
        return t;
    }

    fn toEol(self: *const Lexer, from: usize) usize {
        return std.mem.indexOfScalarPos(u8, self.src, from, '\n') orelse self.src.len;
    }

    pub fn next(self: *Lexer) ?Token {
        if (self.pos >= self.src.len) return null;
        const s = self.src;
        const c = s[self.pos];
        const prev: u8 = if (self.pos > 0) s[self.pos - 1] else '\n';
        const at_boundary = std.ascii.isWhitespace(prev) or std.mem.indexOfScalar(u8, "|;(&{=,", prev) != null;

        // Whitespace (a newline starts a fresh line).
        if (std.ascii.isWhitespace(c)) {
            var e = self.pos;
            var nl = false;
            while (e < s.len and std.ascii.isWhitespace(s[e])) : (e += 1) {
                if (s[e] == '\n') nl = true;
            }
            const t: Token = .{ .kind = .plain, .text = s[self.pos..e] };
            self.pos = e;
            if (nl) self.line_start = true;
            return t;
        }

        // Comments.
        switch (self.lang) {
            .powershell, .bash => if (c == '#' and (self.lang == .powershell or at_boundary)) return self.take(self.toEol(self.pos) - self.pos, .comment),
            .cmd => {
                if (self.line_start and std.mem.startsWith(u8, s[self.pos..], "::")) return self.take(self.toEol(self.pos) - self.pos, .comment);
                if (self.line_start and s.len - self.pos >= 3 and std.ascii.eqlIgnoreCase(s[self.pos..][0..3], "rem") and (s.len - self.pos == 3 or std.ascii.isWhitespace(s[self.pos + 3]))) return self.take(self.toEol(self.pos) - self.pos, .comment);
            },
            .generic => if (c == '#' and at_boundary) return self.take(self.toEol(self.pos) - self.pos, .comment),
        }

        // Quoted strings end at the closing quote or the end of the line.
        if (c == '"' or c == '\'') {
            var e = self.pos + 1;
            while (e < s.len and s[e] != '\n') : (e += 1) {
                if (s[e] == c) {
                    e += 1;
                    break;
                }
                // Escapes: backtick in PowerShell, backslash elsewhere (not inside single quotes).
                if (c == '"' and e + 1 < s.len and ((self.lang == .powershell and s[e] == '`') or (self.lang != .powershell and s[e] == '\\'))) e += 1;
            }
            return self.take(e - self.pos, .string);
        }

        // Variables.
        if (c == '$' and self.lang != .cmd and self.pos + 1 < s.len) {
            var e = self.pos + 1;
            if (s[e] == '{') {
                e = (std.mem.indexOfScalarPos(u8, s, e, '}') orelse s.len -| 1) + 1;
            } else if (s[e] == '(') {
                return self.take(1, .plain); // $( ... ): the contents lex normally
            } else {
                while (e < s.len and (std.ascii.isAlphanumeric(s[e]) or s[e] == '_' or s[e] == '?' or s[e] == '@' or s[e] == '*' or (self.lang == .powershell and s[e] == ':'))) : (e += 1) {}
                if (e == self.pos + 1 and std.mem.indexOfScalar(u8, "?@*$#!", s[e]) != null) e += 1;
            }
            if (e > self.pos + 1) return self.take(@min(e, s.len) - self.pos, .variable);
        }
        if (c == '%' and self.lang == .cmd) {
            if (std.mem.indexOfScalarPos(u8, s, self.pos + 1, '%')) |e| {
                const body = s[self.pos + 1 .. e];
                if (e - self.pos < 40 and std.mem.indexOfAny(u8, body, " \t\n") == null) return self.take(e + 1 - self.pos, .variable);
            }
            if (self.pos + 1 < s.len and (std.ascii.isDigit(s[self.pos + 1]) or s[self.pos + 1] == '~')) {
                var e = self.pos + 2;
                while (e < s.len and std.ascii.isAlphanumeric(s[e])) : (e += 1) {}
                return self.take(e - self.pos, .variable);
            }
        }

        // Options: -Name, --name, /x (cmd).
        if (at_boundary and ((c == '-' and self.pos + 1 < s.len and (std.ascii.isAlphabetic(s[self.pos + 1]) or s[self.pos + 1] == '-')) or (c == '/' and self.lang == .cmd and self.pos + 1 < s.len and std.ascii.isAlphabetic(s[self.pos + 1])))) {
            var e = self.pos + 1;
            while (e < s.len and (std.ascii.isAlphanumeric(s[e]) or s[e] == '-' or s[e] == '_')) : (e += 1) {}
            return self.take(e - self.pos, .param);
        }

        // Numbers.
        if (std.ascii.isDigit(c) and !(std.ascii.isAlphanumeric(prev) or prev == '_')) {
            var e = self.pos + 1;
            while (e < s.len and (std.ascii.isAlphanumeric(s[e]) or s[e] == '.')) : (e += 1) {}
            return self.take(e - self.pos, .number);
        }

        // Words: keywords and commands.
        if (isWordStart(c)) {
            var e = self.pos + 1;
            while (e < s.len and self.isWordChar(s[e])) : (e += 1) {}
            // A trailing '.' or '-' belongs to the next token.
            while (e > self.pos + 1 and (s[e - 1] == '.' or s[e - 1] == '-')) e -= 1;
            const w = s[self.pos..e];
            const kind: Kind = switch (self.lang) {
                .powershell => if (isCmdlet(w)) .command else if (inList(&ps_keywords, w, true) and !std.ascii.isUpper(w[0])) .keyword else .plain,
                .bash => if (inList(&bash_keywords, w, false)) .keyword else .plain,
                .cmd => if (inList(&cmd_keywords, w, true)) .keyword else .plain,
                .generic => .plain,
            };
            return self.take(e - self.pos, kind);
        }
        return self.take(1, .plain);
    }
};

fn expectKinds(src: []const u8, lang: Lang, want: []const [2][]const u8) !void {
    var lx = Lexer.init(src, lang);
    var total: usize = 0;
    var seen: std.ArrayList(Token) = .empty;
    defer seen.deinit(std.testing.allocator);
    while (lx.next()) |t| {
        total += t.text.len;
        try seen.append(std.testing.allocator, t);
    }
    // Lossless: every byte is in exactly one token.
    try std.testing.expectEqual(src.len, total);
    for (want) |w| {
        var found = false;
        for (seen.items) |t| {
            if (std.mem.eql(u8, t.text, w[1]) and std.mem.eql(u8, @tagName(t.kind), w[0])) found = true;
        }
        if (!found) {
            std.debug.print("missing {s} '{s}'\n", .{ w[0], w[1] });
            return error.TestExpectedEqual;
        }
    }
}

test "powershell" {
    try expectKinds("Get-Service -Name 'Spooler' | Where-Object { $_.Status -eq 'Running' } # done\nif ($x -gt 3) { $env:Path }", .powershell, &.{
        .{ "command", "Get-Service" },  .{ "param", "-Name" },    .{ "string", "'Spooler'" },
        .{ "command", "Where-Object" }, .{ "variable", "$_" },    .{ "param", "-eq" },
        .{ "comment", "# done" },       .{ "keyword", "if" },     .{ "number", "3" },
        .{ "variable", "$env:Path" },
    });
}

test "bash" {
    try expectKinds("for f in *.log; do echo \"$f\" # note\ndone\nls --all -l", .bash, &.{
        .{ "keyword", "for" }, .{ "keyword", "do" },      .{ "string", "\"$f\"" },
        .{ "comment", "# note" }, .{ "keyword", "done" }, .{ "param", "--all" },
        .{ "param", "-l" },
    });
}

test "cmd" {
    try expectKinds("REM hello\n@echo off\nset X=%PATH%\nif exist C:\\x (dir /b)", .cmd, &.{
        .{ "comment", "REM hello" }, .{ "keyword", "echo" }, .{ "variable", "%PATH%" },
        .{ "keyword", "exist" },     .{ "param", "/b" },
    });
}

test "language detection" {
    try std.testing.expectEqual(Lang.powershell, langFor("powershell", ""));
    try std.testing.expectEqual(Lang.powershell, langFor("", "Get-Process | Sort-Object CPU"));
    try std.testing.expectEqual(Lang.cmd, langFor("", "echo %USERPROFILE%"));
    try std.testing.expectEqual(Lang.bash, langFor("sh", ""));
    try std.testing.expectEqual(Lang.generic, langFor("toml", "x = 1"));
    try std.testing.expectEqual(Lang.generic, langFor("", "plain words"));
}
