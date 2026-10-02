# Strict recursive-descent SYNTAX checker for the Luau subset used by War State.
# Covers: locals / functions / methods, if-elseif-else, while, numeric + generic for, repeat-until,
# break / continue, compound assignment (+= -= *= /= //= %= ^= ..=), if-expressions, varargs,
# table constructors, method calls, string/table call sugar, interpolated strings, type annotations,
# type casts (::), generics, `type` / `export type` aliases, function types, optional types (?),
# unions / intersections. It does NOT type-check; it catches real syntax errors (missing `end`,
# `then`, `do`, commas, stray tokens, bad assignments) that the heuristic checker can miss.

import re

KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
}

TOKEN_RE = re.compile(
    r"""
    (?P<ws>[ \t\r\f\v]+)
  | (?P<nl>\n)
  | (?P<number>0[xX][0-9a-fA-F_]+|0[bB][01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.\.|\.\.=|//=|::|->|==|~=|<=|>=|\+=|-=|\*=|/=|%=|\^=|//|\.\.|[-+*/%\^\#<>=(){}\[\];:,.?|&])
    """,
    re.X,
)


class LuauSyntaxError(Exception):
    pass


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind = kind
        self.value = value
        self.line = line

    def __repr__(self):
        return "%s(%r)@%d" % (self.kind, self.value, self.line)


def tokenize(src):
    toks = []
    i, n, line = 0, len(src), 1
    while i < n:
        ch = src[i]
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                end = src.find(close, i + len(m.group(0)))
                if end == -1:
                    raise LuauSyntaxError("unterminated block comment on line %d" % line)
                line += src.count("\n", i, end)
                i = end + len(close)
            else:
                end = src.find("\n", i)
                i = n if end == -1 else end
            continue
        if ch == "[":
            m = re.match(r"\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                end = src.find(close, i + len(m.group(0)))
                if end == -1:
                    raise LuauSyntaxError("unterminated long string on line %d" % line)
                toks.append(Tok("string", src[i:end + len(close)], line))
                line += src.count("\n", i, end)
                i = end + len(close)
                continue
        if ch in "\"'`":
            quote = ch
            j = i + 1
            depth = 0
            while j < n:
                c = src[j]
                if c == "\\":
                    j += 2
                    continue
                if c == "\n" and quote != "`":
                    raise LuauSyntaxError("unterminated string on line %d" % line)
                if quote == "`" and c == "{":
                    depth += 1
                elif quote == "`" and c == "}" and depth > 0:
                    depth -= 1
                elif c == quote and depth == 0:
                    break
                j += 1
            if j >= n:
                raise LuauSyntaxError("unterminated string on line %d" % line)
            toks.append(Tok("string", src[i:j + 1], line))
            line += src.count("\n", i, j)
            i = j + 1
            continue
        m = TOKEN_RE.match(src, i)
        if not m:
            raise LuauSyntaxError("unexpected character %r on line %d" % (ch, line))
        kind = m.lastgroup
        value = m.group(0)
        if kind == "nl":
            line += 1
        elif kind == "ws":
            pass
        elif kind == "name":
            toks.append(Tok("keyword" if value in KEYWORDS else "name", value, line))
        else:
            toks.append(Tok(kind, value, line))
        i = m.end()
    toks.append(Tok("eof", "<eof>", line))
    return toks


BINARY = {"+", "-", "*", "/", "//", "%", "^", "..", "==", "~=", "<", "<=", ">", ">=", "and", "or"}
COMPOUND = {"+=", "-=", "*=", "/=", "//=", "%=", "^=", "..="}
BLOCK_END = {"end", "else", "elseif", "until", "<eof>"}


class Parser:
    def __init__(self, src):
        self.toks = tokenize(src)
        self.i = 0

    # helpers -----------------------------------------------------------------
    @property
    def tok(self):
        return self.toks[self.i]

    def peek(self, k=1):
        return self.toks[min(self.i + k, len(self.toks) - 1)]

    def check(self, value):
        t = self.tok
        return t.value == value and t.kind in ("op", "keyword")

    def accept(self, value):
        if self.check(value):
            self.i += 1
            return True
        return False

    def expect(self, value, context=""):
        if not self.accept(value):
            raise LuauSyntaxError(
                "expected '%s'%s near '%s' on line %d" % (value, (" " + context) if context else "", self.tok.value, self.tok.line)
            )

    def name(self):
        t = self.tok
        if t.kind != "name":
            raise LuauSyntaxError("expected a name near '%s' on line %d" % (t.value, t.line))
        self.i += 1
        return t.value

    # blocks ------------------------------------------------------------------
    def chunk(self):
        self.block()
        if self.tok.kind != "eof":
            raise LuauSyntaxError("unexpected '%s' on line %d" % (self.tok.value, self.tok.line))

    def block_ends(self):
        t = self.tok
        return t.kind == "eof" or (t.kind == "keyword" and t.value in BLOCK_END)

    def block(self):
        while not self.block_ends():
            if self.check("return"):
                self.i += 1
                if not self.block_ends() and not self.check(";"):
                    self.explist()
                self.accept(";")
                if not self.block_ends():
                    raise LuauSyntaxError("'return' must be the last statement (line %d)" % self.tok.line)
                return
            if self.check("break"):
                self.i += 1
                self.accept(";")
                continue
            self.statement()
            self.accept(";")

    def statement(self):
        t = self.tok
        if t.kind == "keyword":
            v = t.value
            if v == "local":
                self.i += 1
                if self.accept("function"):
                    self.name()
                    self.funcbody()
                    return
                self.typed_name()
                while self.accept(","):
                    self.typed_name()
                if self.accept("="):
                    self.explist()
                return
            if v == "function":
                self.i += 1
                self.name()
                while self.accept("."):
                    self.name()
                if self.accept(":"):
                    self.name()
                self.funcbody()
                return
            if v == "if":
                self.i += 1
                self.expr()
                self.expect("then", "after if condition")
                self.block()
                while self.accept("elseif"):
                    self.expr()
                    self.expect("then", "after elseif condition")
                    self.block()
                if self.accept("else"):
                    self.block()
                self.expect("end", "to close 'if'")
                return
            if v == "while":
                self.i += 1
                self.expr()
                self.expect("do", "after while condition")
                self.block()
                self.expect("end", "to close 'while'")
                return
            if v == "do":
                self.i += 1
                self.block()
                self.expect("end", "to close 'do'")
                return
            if v == "for":
                self.i += 1
                self.typed_name()
                if self.accept("="):
                    self.expr()
                    self.expect(",", "in numeric for")
                    self.expr()
                    if self.accept(","):
                        self.expr()
                else:
                    while self.accept(","):
                        self.typed_name()
                    self.expect("in", "in generic for")
                    self.explist()
                self.expect("do", "in for loop")
                self.block()
                self.expect("end", "to close 'for'")
                return
            if v == "repeat":
                self.i += 1
                self.block()
                self.expect("until", "to close 'repeat'")
                self.expr()
                return
            raise LuauSyntaxError("unexpected '%s' on line %d" % (v, t.line))
        if t.kind == "name":
            nxt = self.peek()
            if t.value == "continue" and not (nxt.kind == "op" and nxt.value in ("(", "=", ".", ":", "[", ",", "{")) and nxt.kind != "string":
                self.i += 1
                return
            if t.value == "export" and nxt.kind == "name" and nxt.value == "type":
                self.i += 1
                t = self.tok
                nxt = self.peek()
            if t.value == "type" and nxt.kind == "name":
                self.i += 1
                self.name()
                if self.accept("<"):
                    self.generic_list()
                self.expect("=", "in type alias")
                self.type_()
                return
        # expression statement: assignment or call
        is_call = self.suffixedexp()
        if self.check("=") or self.check(","):
            while self.accept(","):
                self.suffixedexp()
            self.expect("=", "in assignment")
            self.explist()
            return
        if self.tok.kind == "op" and self.tok.value in COMPOUND:
            self.i += 1
            self.expr()
            return
        if not is_call:
            raise LuauSyntaxError("syntax error near '%s' on line %d (expression is not a statement)" % (self.tok.value, self.tok.line))

    def typed_name(self):
        self.name()
        if self.accept(":"):
            self.type_()

    def generic_list(self):
        # after '<'
        while True:
            if self.accept("..."):
                pass
            else:
                self.name()
                self.accept("...")
                if self.accept("="):
                    self.type_()
            if not self.accept(","):
                break
        self.expect(">", "to close generics")

    def funcbody(self):
        if self.accept("<"):
            self.generic_list()
        self.expect("(", "to open parameter list")
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    if self.accept(":"):
                        self.type_()
                    break
                self.typed_name()
                if not self.accept(","):
                    break
        self.expect(")", "to close parameter list")
        if self.accept(":"):
            self.return_type()
        self.block()
        self.expect("end", "to close 'function'")

    # expressions -------------------------------------------------------------
    def explist(self):
        self.expr()
        while self.accept(","):
            self.expr()

    def expr(self):
        self.unary()
        while (self.tok.kind == "op" and self.tok.value in BINARY) or (self.tok.kind == "keyword" and self.tok.value in ("and", "or")):
            self.i += 1
            self.unary()

    def unary(self):
        if self.check("not") or self.check("-") or self.check("#"):
            self.i += 1
            self.unary()
            return
        self.simple()

    def simple(self):
        t = self.tok
        if t.kind in ("number", "string"):
            self.i += 1
        elif t.kind == "keyword" and t.value in ("nil", "true", "false"):
            self.i += 1
        elif self.check("..."):
            self.i += 1
        elif self.check("{"):
            self.table()
        elif self.check("function"):
            self.i += 1
            self.funcbody()
        elif self.check("if"):
            self.i += 1
            self.expr()
            self.expect("then", "in if-expression")
            self.expr()
            while self.accept("elseif"):
                self.expr()
                self.expect("then", "in if-expression")
                self.expr()
            self.expect("else", "in if-expression (else is required)")
            self.expr()
        else:
            self.suffixedexp()
        if self.accept("::"):
            self.type_()

    def primary(self):
        if self.tok.kind == "name":
            self.i += 1
            return
        if self.accept("("):
            self.expr()
            self.expect(")", "to close parenthesis")
            return
        raise LuauSyntaxError("unexpected '%s' on line %d" % (self.tok.value, self.tok.line))

    def suffixedexp(self):
        """Returns True when the expression ends with a call."""
        self.primary()
        is_call = False
        while True:
            if self.accept("."):
                self.name()
                is_call = False
            elif self.check("[") and not re.match(r"\[=*\[", self.tok.value):
                self.i += 1
                self.expr()
                self.expect("]", "to close index")
                is_call = False
            elif self.accept(":"):
                self.name()
                self.callargs()
                is_call = True
            elif self.check("(") or self.check("{") or self.tok.kind == "string":
                # Lua rule: a call's '(' must be on the same line is not enforced here.
                self.callargs()
                is_call = True
            else:
                return is_call

    def callargs(self):
        if self.tok.kind == "string":
            self.i += 1
            return
        if self.check("{"):
            self.table()
            return
        self.expect("(", "to open call arguments")
        if not self.check(")"):
            self.explist()
        self.expect(")", "to close call arguments")

    def table(self):
        self.expect("{")
        while not self.check("}"):
            if self.accept("["):
                self.expr()
                self.expect("]", "in table key")
                self.expect("=", "after table key")
                self.expr()
            elif self.tok.kind == "name" and self.peek().kind == "op" and self.peek().value == "=":
                self.i += 2
                self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", "to close table")

    # types -------------------------------------------------------------------
    def return_type(self):
        self.type_()

    def type_(self):
        self.accept("|")
        self.accept("&")
        self.simple_type()
        while self.accept("|") or self.accept("&"):
            self.simple_type()

    def simple_type(self):
        t = self.tok
        if t.kind == "name" and t.value == "typeof" and self.peek().value == "(":
            self.i += 1
            self.expect("(")
            self.expr()
            self.expect(")")
        elif t.kind == "name":
            self.i += 1
            if self.accept("."):
                self.name()
            if self.accept("<"):
                self.type_list_until(">")
        elif t.kind == "keyword" and t.value in ("nil", "true", "false"):
            self.i += 1
        elif t.kind == "string":
            self.i += 1
        elif self.check("{"):
            self.table_type()
        elif self.check("("):
            self.i += 1
            if not self.check(")"):
                while True:
                    if self.tok.kind == "name" and self.peek().value == ":" and self.peek().kind == "op":
                        self.i += 2
                    if self.accept("..."):
                        self.type_()
                    else:
                        self.type_()
                    if not self.accept(","):
                        break
            self.expect(")", "to close type")
            if self.accept("->"):
                self.type_()
        elif self.check("..."):
            self.i += 1
            self.type_()
        elif self.check("<"):
            self.i += 1
            self.generic_list()
            self.simple_type()
        else:
            raise LuauSyntaxError("expected a type near '%s' on line %d" % (t.value, t.line))
        while self.accept("?"):
            pass

    def type_list_until(self, closer):
        if not self.check(closer):
            while True:
                if self.accept("..."):
                    self.type_()
                else:
                    self.type_()
                if not self.accept(","):
                    break
        self.expect(closer, "to close type arguments")

    def table_type(self):
        self.expect("{")
        while not self.check("}"):
            if self.accept("["):
                self.type_()
                self.expect("]")
                self.expect(":", "in table type")
                self.type_()
            elif self.tok.kind in ("name", "keyword") and self.peek().kind == "op" and self.peek().value == ":":
                self.i += 2
                self.type_()
            else:
                self.type_()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}", "to close table type")


def parse_luau(src):
    """Returns a list with one error string, or [] when the source parses."""
    try:
        Parser(src).chunk()
    except LuauSyntaxError as exc:
        return [str(exc)]
    return []

