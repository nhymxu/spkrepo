# Third-party notice

`functions` and `installer.dsm7` in this directory are vendored verbatim
(unmodified) from [SynoCommunity/spksrc](https://github.com/SynoCommunity/spksrc)
`mk/spksrc.service/`, retrieved 2026-07-20. `start-stop-status` is also
vendored verbatim from the same location. `preinst`, `postinst`,
`preuninst`, `postuninst`, `preupgrade`, and `postupgrade` are original
(this repo, not spksrc) but generic, app-agnostic wrappers -- each just
sources `installer.dsm7` and calls the matching lifecycle function --
kept here rather than duplicated per package under `packages/<app>/`.

Every package under `packages/` copies all of these files verbatim into
its `.spk`'s `scripts/` directory at build time, then adds its own
package-specific `service-setup` file alongside them (see e.g.
`packages/forgejo/build.sh`).

spksrc license (3-clause BSD):

```
Copyright (c) 2011, Sebastien Erard
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
* Neither the name of the zebulon nor the names of its contributors may
  be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
