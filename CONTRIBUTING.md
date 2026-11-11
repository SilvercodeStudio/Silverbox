# Contributing to Silverbox

Thank you for your interest in Silverbox. Bug reports, ideas, and pull
requests are welcome. For a large change, open an issue first, so that we
can talk about it before you do the work.

## The license of your contribution

Silverbox ships under the GNU General Public License, version 3 or later
(see [LICENSE](LICENSE) and [NOTICE](NOTICE)). Contributions come in under a
simpler license, the MIT License:

- When you send a contribution to Silverbox (a pull request, a patch, or code
  in an issue or in any other way), you license it to the project under the
  MIT License, with the text below.
- Silverbox then ships your contribution under the GPL, as part of the
  project.
- The author of Silverbox, Preston Landers, keeps the right to use your
  contribution under other licenses too, in Silverbox or in other work.
- You keep the copyright in your contribution.

When you send a contribution, you agree to these terms.

## The MIT License, for contributions

Copyright (c) the contributor, for each contribution

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Before you send a change

- Run `make format`, `make lint`, and `make test`. Lint must be clean, and
  the app must build (`make build`).
- Add a line to [CHANGELOG.md](CHANGELOG.md) when you change what people see
  or can do.
- Talk with us before you add an outside dependency or any network use.
- Don't copy code from GPL programs or other copyleft code, such as DOSBox,
  86Box, ScummVM or most emulators. Read them to understand a format, then
  write your own. Copied copyleft code would stop the project from using
  your contribution under other licenses.
