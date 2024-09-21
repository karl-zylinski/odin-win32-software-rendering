# Win32 software rendering in Odin

![software_render](https://github.com/user-attachments/assets/68651631-e409-47b3-b1d3-dded7894a21a)

Opens a Windows window and sets up software rendering. Only dependency is Odin's core collection.

The software rendering uses a bitmap that has a 2 color palette (kind-of 1 bit colors).

Does some simple video game stuff where an animation is drawn using a texture loaded from disk. It can also draw rectangles. There's a bunch of comments in `win32_software_rendering.odin` that explains how it works.

Compile and run by using `odin run .` or by using the built in Sublime Text project file.

By Karl Zylinski, http://zylinski.se -- Support me at https://www.patreon.com/karl_zylinski
