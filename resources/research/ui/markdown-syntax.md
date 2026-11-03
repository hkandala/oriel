---
title: Markdown syntax fixture
---

# Heading 1 (ATX)

## Heading 2 with a closing sequence ##

### Heading 3

#### Heading 4

##### Heading 5

###### Heading 6

Setext heading 1
================

Setext heading 2
----------------

## Paragraphs and breaks

A paragraph whose source is wrapped at a narrow width, so this sentence
goes on in the next source line and the one after that, as most
documentation is written. It must flow as one paragraph.

A hard break with two trailing spaces  
and one with a backslash\
then the paragraph ends.

## Emphasis

Some *italic* and _italic_, **bold** and __bold__, ***bold italic***, **bold with _nested italic_**,
~~strikethrough~~, intra*word*emphasis, and snake_case_words that stay plain.

## Links

- Inline: [Oriel](https://oriel.dev) and [with a title](https://oriel.dev "The title").
- Reference, full: [the docs][docs]; collapsed: [docs][]; shortcut: [docs].
- Autolinks: <https://example.com> and <mail@example.com>.
- Bare (GFM): https://example.com/path and www.example.com.
- Relative: [other file](other.md) and an anchor: [to Tables](#tables).
- An address on the next line: [split](
  https://example.com).

[docs]: https://oriel.dev/docs "Oriel docs"

## Images

![An image's alt text](image.png "Its title") and a reference image ![logo][logo].

[logo]: logo.png

## Code

Inline `code`, ``code with a ` tick``, and `<b>not html</b>`.

```swift
let greeting = "Hello"
print(greeting)
```

~~~
A tilde fence with no language.
~~~

    An indented code block,
    four spaces deep.

## Block quotes

> A quote with **bold** text that is long enough to wrap onto a second line in a narrow card like
> this one.
>
> - A list inside the quote
> - Its second item
>
> > A nested quote.
>
> - A quoted item
>
>   with a second paragraph.
>
> ```sh
> make lint
> ```

## Lists

- A plain bullet that is long enough to wrap onto a second line in a narrow card like this one and
  goes on in a second source line, indented under the text.
- Second bullet
  - A nested bullet
    - A third level
* A star bullet starts a new list
+ A plus bullet starts another

1. First numbered item with a continuation line in the source
   that is indented by three spaces.
2. Second

   A second paragraph in the second item.
3. Third

A paragraph ends that list. Ones count up:

1. One
1. One again (renders as 2)
1. And again (renders as 3)

A list can start at any number:

7. A list that starts at seven
8. Eight

Parentheses (they render as dots):

1) A list with parentheses
2) Two

- An item with a quote:
  > quoted under the item's text,
  > on two lines.
- An item with code and a table:

  ```sh
  make test
  ```

  | Key | Value |
  |-----|-------|
  | a   | 1     |

- [ ] An open task
- [x] A done task with a long label that wraps onto a second line in a narrow card like this one
  - [ ] A nested task

## Tables

| Plugin | Label argument | Page | Tab |
|:-------|:--------------:|-----:|-----|
| `explorer` | a folder's absolute path, ending in `/` | the tree, rooted there | `File Explorer oriel` |
| `git` | the repository's root | the Git home | `Git oriel` |

## HTML

<details>
<summary>An HTML block</summary>

Inside the block.

```sh
make e2e
```

</details>

<!-- An HTML comment draws nothing. -->

Inline HTML: <kbd>⌘</kbd><kbd>E</kbd>, H<sub>2</sub>O, x<sup>2</sup>, <b>bold</b> and a<br>break, a tag
<a
href="https://example.com">split over lines</a>, <b><b>nested</b> tags</b> and a comment <!-- over
two lines --> that draws nothing.

## Footnotes

A sentence with a footnote.[^1] And a second one.[^note] A third is a source.[^src]

[^1]: The first footnote.
[^note]: The second footnote, with a longer text.

[^src]: https://example.com/source

## Rules

Text above three rules.

***

___

- - -

## Entities and escapes

&copy; &amp; &lt;tag&gt; &#169; &#xA9; &nbsp;and \*not italic\* and \# not a heading. A path that ends in a
backslash, C:\\
flows on.

## Tables (a second heading of the same name)

The link [to the second Tables](#tables-1) goes here.
