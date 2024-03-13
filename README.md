# CPM-View
Fast and compact file viewer for CP/M.  Intended for Z80 based CP/M computers using VT100/ANSI terminals or VT100/ANSI emulated terminals.  Supports cursor, PgUp/PgDn and Home/End keys.  Source can be assembled with either TASM or ZMAC cross assemblers.  View supports 24 lines and View48 supports 48 lines.

This viewer is derived from the JED text editor. The Z80 code has been minimized for viewing files only with no syntax highlighting.  Use Jed for syntax highlighting.  See https://github.com/z80playground/jed for the original source. All viewer source code is contained in a single file (no includes).  The file to be viewed must fit into available memory but the viewer executable itself is only 2300 bytes.

Install: LOAD VIEW.HEX
Usage:   VIEW <filename.ext>
Exit:    Q or X or ^C
