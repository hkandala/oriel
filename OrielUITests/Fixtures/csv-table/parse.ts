/** Rows of fields. Quotes may wrap a field; "" inside quotes is one quote. */
export function parse(text: string, separator: string): string[][] {
  const rows: string[][] = [[]]
  let field = "", quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (c === '"') quoted = false
      else field += c
    } else if (c === '"') quoted = true
    else if (c === separator) { rows.at(-1)!.push(field); field = "" }
    else if (c === "\n") { rows.at(-1)!.push(field.replace(/\r$/, "")); rows.push([]); field = "" }
    else field += c
  }
  rows.at(-1)!.push(field)
  return rows.filter((row) => row.some((cell) => cell !== ""))
}
