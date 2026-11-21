# Third-party notices

Yab includes software from the following projects, under the licenses below.

## SwiftTerm

The Development Space terminal uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

```
Copyright (c) 2019-2026 Miguel de Icaza (https://github.com/migueldeicaza)
Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
Copyright (c) 2016 Ryan L McIntyre (Powerline Extra Symbols flame silhouette, https://github.com/ryanoasis/powerline-extra-symbols)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Ionicons

https://github.com/ionic-team/ionicons. Twenty-five space icon drawings in
Sources/Fast/SpaceIconArt.swift are Ionicons glyphs, drawn from ionicons.ttf.

```
The MIT License (MIT)

Copyright (c) 2015-present Ionic (http://ionic.io/)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## Central Icon System

https://centralicons.com/. Copyright David & Storm GbR, iconists. Yab's
interface icons on the Mac, iPhone and Android are drawn from the Central
Icon System, used under the owner's purchased license: the paths in
`Sources/YabDesign/Glyphs.swift`, `Sources/Fast/IconMarks.swift` and
`Sources/Fast/SpaceIconArt.swift`, the SVGs in `Phone/Resources/Icons/`, the
image sets in `Phone/Sources/Design/Glyphs.xcassets` and
`MacGlyphs.xcassets`, and `Android/scripts/glyphs-central.json` with
`YabGlyphs.kt`. These assets are not covered by Yab's Apache License; their
license does not allow reusing them outside Yab.

---

## theSVG

[theSVG](https://thesvg.org/) supplies the Antigravity, Codex, Figma, GitHub,
Notion, and Vercel marks in `Sources/YabDesign/Glyphs.swift`. The marks
remain trademarks of their respective owners.

```
MIT License

Copyright (c) 2025 thesvg.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## OpenUI and React

Development chat renders optional OpenUI Lang replies with the official
[OpenUI](https://github.com/thesysdev/openui) React renderer and component
library. OpenUI and [React](https://github.com/facebook/react) are MIT
licensed. The app bundles their license files and the renderer's
dependency notices in `Contents/Resources/OpenUI`.

## Yab (original source)

```
MIT License

Copyright (c) 2026 Office Commun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Lean

https://github.com/DeepanshuMishraa/lean. The YouTube ad script (Sources/Fast/YouTube.swift)
and the YouTube entries of the ad blocker's built-in list (Shield.swift) are
adapted from Lean's PageScripts.swift and ContentBlocker.swift.

```
MIT License

Copyright (c) 2026 Deepanshu Mishra

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## BIN List Data

https://github.com/venelinkochev/bin-list-data. The card issuer table
(Resources/bins.dat, read by Sources/Fast/Bins.swift) is packed from its
bin-list-data.csv: each BIN's issuer, card level and type, with issuer names
shortened. Licensed under the Creative Commons Attribution 4.0 International
License, https://creativecommons.org/licenses/by/4.0/.

---

## Unicode CLDR

https://github.com/unicode-org/cldr-json. Emoji's words (Resources/emoji.dat,
read by Sources/Fast/EmojiMeaning.swift) are packed by Resources/emoji-pack.py
from CLDR's English emoji annotations, release 48.2. Change Icon's emoji
(Resources/emoji-groups.dat, read by Sources/Fast/IconPicker.swift) are
packed by Resources/emoji-groups-pack.py from Unicode's emoji-test.txt,
version 18.0. Copyright © 1991-2026 Unicode, Inc. Licensed under the Unicode
License v3, https://www.unicode.org/license.txt.

---

## Caveat

https://github.com/googlefonts/caveat. The hand an update's note is written in
(Resources/Caveat.ttf, read by Sources/Fast/UpdateDoodle.swift), and the pen's
note in Yab for iPhone's first run (Phone/Sources/Design/Caveat.ttf, read by
Phone/Sources/Welcome/FirstRun.swift), is Caveat's variable font as Google
Fonts publishes it, unchanged.

```
Copyright 2014 The Caveat Project Authors (https://github.com/googlefonts/caveat)

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
http://scripts.sil.org/OFL


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```


## Dark Reader

Dark pages use Dark Reader's engine (the npm package `darkreader`) and its
site lists (`dynamic-theme-fixes.config`, `dark-sites.config`).
https://github.com/darkreader/darkreader

```
MIT License

Copyright (c) 2026 Dark Reader Ltd.

All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```


## CodeMirror 6

The DevTools source editor includes CodeMirror 6 packages, copyright Marijn Haverbeke and contributors, distributed under the MIT license. https://codemirror.net/


## axe-core

Developer Tools accessibility audits bundle axe-core, copyright Deque Systems, Inc., licensed under MPL-2.0. The license is included in Resources/DevTools/axe-LICENSE. https://github.com/dequelabs/axe-core

Heap snapshot graph analysis uses WebKit's `HeapSnapshot.js` worker algorithm
(BSD 3-Clause, Google Inc. and Apple Inc.). The complete copyright notice and
license are retained in `Resources/DevTools/heap-snapshot.js`.
Source: https://github.com/WebKit/WebKit/blob/main/Source/WebInspectorUI/UserInterface/Workers/HeapSnapshot/HeapSnapshot.js


## GeckoView

`Android/engine-gecko/` holds files and a patch from Mozilla's GeckoView,
licensed under the Mozilla Public License 2.0; each file keeps its license
header. https://mozilla.org/MPL/2.0/

## Chromium and the Chromium Embedded Framework

`YabCore/cef-patches/` holds patches to Chromium and CEF, under their
BSD 3-Clause licenses (Copyright The Chromium Authors; Copyright Marshall A.
Greenblatt). The CEF binary distribution is downloaded at build time by
`scripts/cef/fetch.sh`, not kept in this repository; its own license and the
Chromium third-party notices ship inside it.
