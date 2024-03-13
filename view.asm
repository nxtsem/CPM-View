; This viewer is derived from the JED.COM text editor (search for "-mod"). 
; The code has been minimized for viewing files only with no highlighting.
; See https://github.com/z80playground/jed for the original source.
; All viewer source code is contained in a single file (no includes).
;
; The max file length is 65535 lines.  The max line length is 255 chars.
; Whole file needs to fit in memory, so can't edit a file bigger than that.
; When you load a file it is arranged like this... The [] are control chars
;
; [START_OF_TEXT]
; line one[EOL]
; line two goes here[EOL]
; [EOL]
; previous line was blank[END_OF_TEXT]
;
; Keep track of the number of lines in the doc in the variable doc_lines.
; No lines wrap, so doc_lines = total lines in the editor.
; There is a cursor that can move around inside the document. 
; Top-most location is 0,0. There is also a doc_pointer that points to the 
; current char that the cursor is on. The current view of the document is 
; displayed on the screen in an area VIEW_WIDTH x VIEW_HEIGHT.
;
; The keys that can be used in this viewer are:
; Any letter/number/symbol in the range ASCII 33 to 128
; Cursor keys: Arrow Up, Arrow Down, Arrow Left, Arrow Right.
; Home, moves to first non-blank character in the line, then to the 
; start of the line.   End, moves to the end of the current line.
; Page Up, moves up a page.  Page Down, moves down a page.
; Q, Ctrl-Q, X, Ctrl-X or Ctrl-C exits the viewer.
;
    .org $0100
    jp main_program

VIEW_HEIGHT:   .db 24        ;24 for normal monitors  -mod
VIEW_WIDTH:    .db 80

; This is the key-definition table, that ties keystrokes to user actions.
; Each row shows the values that come from the keyboard, which can 
; be up to 4 hex values, followed by $00s, followed by action itself.
; You can change the key defs by editing here and re-assembling.
; You can use jedconf.com to determine your keyboard codes.

keytable: 
   .db $0D, $00, $00, $00, $00, ENTER  ;decrease keytable size by 14x4 bytes
   .db $09, $00, $00, $00, $00, TAB
   .db $08, $00, $00, $00, $00, BACKSPACE          ;^H
   .db $03, $00, $00, $00, $00, CTRLC              ;^C was USER_DELETE
   .db $1B, $5B, $41, $00, $00, USER_CURSOR_UP
   .db $1B, $5B, $42, $00, $00, USER_CURSOR_DOWN
   .db $1B, $5B, $44, $00, $00, USER_CURSOR_LEFT
   .db $1B, $5B, $43, $00, $00, USER_CURSOR_RIGHT
   .db $1B, $5B, $31, $7E, $00, USER_CURSOR_HOME
   .db $1B, $5B, $34, $7E, $00, USER_CURSOR_END
   .db $1B, $5B, $35, $7E, $00, USER_CURSOR_PGUP
   .db $1B, $5B, $36, $7E, $00, USER_CURSOR_PGDN
   .db $18, $00, $00, $00, $00, USER_QUIT          ;^X
   .db $11, $00, $00, $00, $00, USER_QUIT_NO_SAVE  ;^Q
   .db $00
;original keytable:    ;allows up to 8 hex values
;   db $0D, $00, $00, $00, $00, $00, $00, $00, $00, ENTER
; ...

; CONSTANTS
TAB_WIDTH             .equ 8
TAB_MASK              .equ 00000111b
CTRLC                 .equ 3       ; ^C
BACKSPACE             .equ 8       ; was $7F -mod
TAB                   .equ 9
LF                    .equ 10
ENTER                 .equ 13
EOL                   .equ 13      ;  ie. CR
END_OF_TEXT           .equ 26
ESC                   .equ 27
START_OF_TEXT         .equ 31
BLACK                 .equ '0'
GREEN                 .equ '2'
DEFAULT               .equ '9'

USER_CURSOR_UP        .equ 128
USER_CURSOR_DOWN      .equ 129
USER_CURSOR_LEFT      .equ 130
USER_CURSOR_RIGHT     .equ 131
USER_CURSOR_HOME      .equ 132
USER_CURSOR_END       .equ 133
USER_CURSOR_PGUP      .equ 134
USER_CURSOR_PGDN      .equ 135
USER_DELETE           .equ 136
USER_QUIT             .equ 255
USER_QUIT_NO_SAVE     .equ 254

BDOS                  .equ 5
FCB                   .equ 005CH    ; We use the standard default FCB
DMA                   .equ 0080H    ; Standard DMA area

BDOS_CONSOLE_INPUT    .equ 6
BDOS_Print_String     .equ 9     ; 09,
BDOS_Read_Console_Buf .equ 10    ; 0A,
BDOS_Open_File        .equ 15    ; 0F, 255 = file not found
BDOS_Close_File       .equ 16    ; 10, 255 = file not found
BDOS_Search_for_First .equ 17    ; 11  255 = file not found
BDOS_Delete_File      .equ 19    ; 13, 255 = file not found
BDOS_Read_Sequential  .equ 20    ; 14, 0 = OK
BDOS_Write_Sequential .equ 21    ; 15, 0 = OK
BDOS_Make_File        .equ 22    ; 16, 255 = Disk Full
BDOS_Rename_File      .equ 23    ; 17, 255 = file not found
BDOS_Set_DMA_Address  .equ 26    ; 1A


; Load a file into RAM. We need to know the start and end of the RAM space
; Start is the end of this code+1,  End is BDOS-1
main_program:   
    ld sp, stacktop       ; Set the stack to point to our local stack
    ld hl, 0           
    ld (screen_top), hl   ; reset screen position and cursor pos
    xor a
    ld (screen_left), a
    ld (cursor_y), hl
    ld (cursor_x), a
    ld (want_x), a
    ld hl, (6)      ; Find addr of BDOS-1, which is end of ram, and store it
    dec hl
    ld (ram_end), hl
    ld hl, end_of_code      ; Find addr of start of useable ram and store it
    inc hl
    ld (hl), START_OF_TEXT  ; Put START OF TEXT terminator before file
    inc hl
    ld (hl), END_OF_TEXT    ; Put END OF TEXT terminator after (blank) file
    ld (doc_start), hl
    ld (doc_pointer), hl
    call find_address_of_bios

    ; Clear the doc area
    call clear_selection
    call clear_doc_lines
    ld hl, (doc_start)
    ld (doc_pointer), hl
    ld (doc_end), hl

    call clear_keybuff
    call was_filename_provided
    call z, load_file
    call show_screen
main_loop:
    call show_screen_if_scrolled
main_loop_no_scroll_change:
    call set_cursor_position
main_loop_get_key:
    call get_user_action
    or a
    jr z, main_loop_get_key
	
;   cp USER_DELETE              ; -mod
;   jr z, delete_pressed        
;   cp 127                      ; -mod
;   jp c, insert_char  
		
    cp BACKSPACE	            ; Backspace is also cursor left -mod
    jp z, cursor_left           ; was jp z, backspace_pressed   -mod 
    cp ENTER                    ; Enter is also cursor down     -mod
    jp z, cursor_down           ;                               -mod
	
    cp USER_CURSOR_RIGHT
    jp z, cursor_right
    cp USER_CURSOR_LEFT
    jp z, cursor_left
    cp USER_CURSOR_UP
    jp z, cursor_up
    cp USER_CURSOR_DOWN
    jp z, cursor_down
    cp USER_CURSOR_HOME
    jp z, cursor_home
    cp USER_CURSOR_END
    jp z, cursor_end
    cp USER_CURSOR_PGUP
    jp z, cursor_page_up
    cp USER_CURSOR_PGDN
    jp z, cursor_page_down
	
    cp USER_QUIT_NO_SAVE        ;^Q   -mod
    jr z, exit	
    cp USER_QUIT                ;^X   -mod
    jr z, exit	                ;      
    cp 'Q'                      ; Q and X will also exit  -mod
    jr z, exit
    cp 'X'                      ;
    jr z, exit		
    cp 'q'                      ; q and x will also exit  -mod
    jr z, exit
    cp 'x'                      ;
    jr z, exit		
    cp CTRLC                    ; ^C will exit  -mod
    jr z, exit	
	
    jp main_loop
exit:
    call cls
    jp 0

; Returns Z if a filename was provided by CP/M in the FCB
was_filename_provided:
    ld hl, FCB+1
    ld a, (hl)
    cp ' '
    jr nz, return_Z
    ld de, no_file_entered_msg
    call show_string_de
    jp 0
no_file_entered_msg:
    .db "No filename entered.",13,10,'$'

return_Z:
    cp a                                ; Set Z
    ret

; Check if there is at least 1 byte of memory left.
; Returns Carry set if out of memory.  This preserves A.
any_memory_left:
    ld hl, (ram_end)
    ld de, (doc_end)
    or a                                ; clear carry
    sbc hl, de
    ret

; Show the current line again because it has changed
; Move screen draw position to start of current line
show_current_line:
    call hide_cursor
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a
    sbc hl, de          ; y coord is in l
    ld b, l             ; y coord is now in b
    inc b               ; VT100 screen coords start at 1, but we start at 0
    ld c, 1             ; x coord is in c
    call move_to_xy
    ld hl, (doc_pointer)   ; Now redraw the row
    call skip_to_start_of_line
    ld a, (screen_left)
    ld (current_col), a    ; Keep track of current column we are displaying
    call skip_cols
    ld a, (VIEW_WIDTH)     ; b = cols left to Show
    ld b, a

show_current_line1:
    ld a, (hl)
    cp END_OF_TEXT
    jr z, show_current_line2
    cp EOL 
    jr z, show_current_line2
    cp TAB
    jr z, show_current_line_tab
    bit 7, a                        ; Is bit 7 set?
    jr z, show_current_line_simple  ; Skip next bit if not set
    ld c, a
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '3'
    call print_a
    ld a, '2'
    call print_a
    ld a, 'm'
    call print_a

show_current_line_simple1:
    ld a, c
show_current_line_simple:     
    and 01111111b      ; Clear bit 7 - was %01111111 -mod for assembler
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    inc hl
    djnz show_current_line1
    jr show_current_line_done
show_current_line2:
    ; Fill remainer of row with spaces
    ld a, ' '
    call print_a
    djnz show_current_line2
    jr show_current_line_done
show_current_line_tab:
    ld c, b
    ld a, (current_col)
    and TAB_MASK
    ld b, a
    ld a, TAB_WIDTH
    sub b
    ld b, a                 ; b stores how long a tab is
show_current_line_tab1:
    ld a, ' '               ; show a tab
    call print_a
    dec c
    ld a, (current_col)
    inc a
    ld (current_col), a
    djnz show_current_line_tab1
    inc hl
    ld b, c
    djnz show_current_line1
show_current_line_done:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '0'
    call print_a
    ld a, 'm'
    call print_a
    call show_cursor
    ret

; If cursor is still on the screen then do nothing.
; If moved off the edge, re-position the screen to bring it back on.
show_screen_if_scrolled:
    ld b, 0    ; b <> 0 if we need to redraw the screen
    ld a, (screen_left)    ; Has cursor gone off the left side?
    ld e, a
    ld a, (cursor_x)
    cp e
    jr nc, show_screen_if_scrolled1
 ; If cursor_x < screen_left then screen_left = cursor_x, redraw	
    ld (screen_left), a  
    ld b, 'L'
    jr show_screen_if_scrolled2
	
; Has cursor gone off right side?
; If cursor_x >= screen_left + PAGE_WIDTH then 
;  screen_left = (cursor_x - PAGE_WIDTH) + 1, redraw	
show_screen_if_scrolled1:
    ld a, (screen_left)
    ld e, a
    ld a, (VIEW_WIDTH)
    add a, e
    ld e, a
    ld a, (cursor_x)
    cp e
    jr c, show_screen_if_scrolled2
    ld e, a
    ld a, (VIEW_WIDTH)
    ld d, a
    ld a, e
    sub d
    inc a
    ld (screen_left), a
    ld b, 'R'
	
; Has cursor gone off top? 
; If cursor_y < screen_top then screen_top = cursor_y, redraw	
show_screen_if_scrolled2:    
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a                                ; clear carry
    sbc hl, de
    jr nc, show_screen_if_scrolled3
    ld hl, (cursor_y)
    ld (screen_top), hl
    ld b, 'T'
    jr show_screen_if_scrolled4
	
; Has cursor gone off bottom? If cursor_y >= screen_top + PAGE_HEIGHT
; then screen_top = (cursor_y - PAGE_HEIGHT) + 1, redraw	
show_screen_if_scrolled3:    
    ld hl, (screen_top)
    ld a, (VIEW_HEIGHT)
    ld e, a
    dec e
    ld d, 0
    add hl, de
    ld de, (cursor_y)
    or a                                ; clear carry
    sbc hl, de
    jr nc, show_screen_if_scrolled4
    ld hl, (cursor_y)
    ld d, 0
    ld a, (VIEW_HEIGHT)
    ld e, a
    or a                                ; clear carry
    sbc hl, de
    inc hl
    ld (screen_top), hl
    ld b, 'B'
show_screen_if_scrolled4:
    ld a, b
    or a
    ret z
    call show_screen
    ret

cursor_down:
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                   ; clear carry
    sbc hl, de
    jp nc, main_loop       ; We're at bottom, so can't go any further down.
    ld hl, (cursor_y)      ; Yes we can move down
    inc hl
    ld (cursor_y), hl
    ld hl, (doc_pointer)   ; Update the doc_pointer and cursor_x
    call skip_to_start_of_next_line
    ld a, (want_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

cursor_up:
    ld hl, (cursor_y)
    ld a, l
    or h
    jp z, main_loop
    dec hl
    ld (cursor_y), hl
    ld hl, (doc_pointer)      ; Update the doc_pointer and cursor_x
    call skip_to_start_of_previous_line
    ld a, (want_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    jp main_loop

; Move the cursor left...  Is cursor already at the start of the doc?
cursor_left:
    ld hl, (doc_pointer)
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jp z, main_loop                 ; abort if at start of doc
    ld a, (cursor_x)
    dec a
    ld (cursor_x), a
    ld (want_x), a
    ld a, (hl)
    cp EOL                    ; Are we wrapping back onto previous row?
    jr z, cursor_left_wrap 
    cp TAB                    ; Have we moved onto a tab?
    jr z, cursor_left_tab     ; Normal cursor left....
    ld (doc_pointer), hl
    jp main_loop
	
; Cursor has gone off the left of line x onto end of line x-1
cursor_left_wrap:
    call skip_to_start_of_line
    ld a, 255
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a                ; Set cursor to end of line
    ld (want_x), a
    ld a, (cursor_y)
    dec a
    ld (cursor_y), a
    jp main_loop

; If we hit a tab recalulate the cursor_x position by going to the 
; start of the line and counting along again.
cursor_left_tab:

    call skip_to_start_of_line
    ld a, (cursor_x)
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    ld (want_x), a
    jp main_loop

; Move to the right...If we are at the end of the file, we can't go right
cursor_right:
    ld hl, (doc_pointer)
    ld a, (hl)
    cp END_OF_TEXT
    jp z, main_loop
    ld a, (cursor_x)         ; Move one space right
    inc a
    ld (cursor_x), a
    ld (want_x), a
    ld hl, (doc_pointer)
    ld a, (hl)
    inc hl
    ld (doc_pointer), hl
    cp EOL                   ; but if we were on a CR, wrap to next line
    jr z, cursor_right_wrap
    cp TAB
    jr z, cursor_right_tab   ; If on a tab, move extra spaces if needed
    jp main_loop
	
; Cursor has gone off the end of line x onto start of line x+1	
cursor_right_wrap:
    xor a
    ld (cursor_x), a     ; Set cursor to start of line
    ld (want_x), a
    ld a, (cursor_y)
    inc a
    ld (cursor_y), a     ; On next line
    jp main_loop
cursor_right_tab:
    ld a, (cursor_x)     ; For TAB, we need to end up on a mod-4 boundary
    and TAB_MASK
    jp z, main_loop
    ld a, (cursor_x)
    inc a
    ld (cursor_x), a
    ld (want_x), a
    jr cursor_right_tab

; Move cursor to start of the line. If cursor_x is 0 then do nothing.
; Move cursor_x left to either the first non-space char, or 0.
cursor_home:
    ld a, (cursor_x)
    or a
    jp z, main_loop
    ld hl, (doc_pointer)   ; Check loc of first non-space char on this line
    call skip_to_start_of_line
    call skip_spaces                 ; col into into c, pointer into hl
    ld a, (cursor_x)
    cp c                    ; is the first non-space where we already are?
    jr c, cursor_home_start_of_line  ; If so, go to the start of the line
    jr z, cursor_home_start_of_line  ; Move to first non-space
    ld a, c
    ld (doc_pointer), hl
    ld (cursor_x), a
    ld (want_x), a
    jp main_loop
cursor_home_start_of_line:
    call skip_to_start_of_line
    ld (doc_pointer), hl
    xor a
    ld (cursor_x), a
    ld (want_x), a
    jp main_loop

; Move cursor to the end of the current line.
cursor_end:
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    ld a, 255
    call skip_cols
    ld (doc_pointer), hl
    ld a, c
    ld (cursor_x), a
    ld (want_x), a
    jp main_loop

; Move the cursor down VIEW_HEIGHT-1 rows
cursor_page_down:
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                ; clear carry
    sbc hl, de
    jp nc, main_loop    ; We're at bottom, so can't go any further down.
    ld a, (VIEW_HEIGHT)
    ld b, a
    dec b
cursor_page_down_loop:
    ld hl, (cursor_y)
    ld de, (doc_lines)
    or a                          ; clear carry
    sbc hl, de
    jp nc, cursor_page_down_stop  ; Yes we can move down
    ld hl, (cursor_y)
    inc hl
    ld (cursor_y), hl             ; Update the doc_pointer
    ld hl, (doc_pointer)
    push bc
    call skip_to_start_of_next_line
    pop bc
    ld (doc_pointer), hl
    djnz cursor_page_down_loop
cursor_page_down_stop:
    ld hl, (doc_pointer)
    call skip_to_start_of_line
    call get_line_length   ; length in a, hl still pointing at start of line
    ld b, a
    dec b
    ld a, (want_x)
    cp b
    jr c, cursor_page_down_ok
    jr z, cursor_page_down_ok
    ld a, b
    ld (cursor_x), a
cursor_page_down_ok:
    call skip_cols
    ld (doc_pointer), hl
    jp main_loop


; Move the cursor up VIEW_HEIGHT+1 rows
cursor_page_up:
    ld hl, (cursor_y)
    ld a, l
    or h
    jp z, main_loop
    ld a, (VIEW_HEIGHT)
    ld b, a
    dec b
cursor_page_up_loop:
    ld hl, (cursor_y)
    ld a, l
    or h
    jr z, cursor_page_up_stop  
    dec hl                  ; increase cursor
    ld (cursor_y), hl       ; Update the doc_pointer
    ld hl, (doc_pointer)
    push bc
    call skip_to_start_of_previous_line
    pop bc
    ld (doc_pointer), hl
    djnz cursor_page_up_loop
cursor_page_up_stop:
    ld hl, (doc_pointer)
    call get_line_length  ; length in a, hl still pointing at start of line
    ld b, a
    dec b
    ld a, (want_x)
    cp b
    jr c, cursor_page_up_ok
    jr z, cursor_page_up_ok
    ld a, b
    ld (cursor_x), a
cursor_page_up_ok:
    call skip_cols
    ld (doc_pointer), hl
    jp main_loop

; Put the cursor on the screen at the correct position.
; This is calculated by cursor_x - screen_left, cursor_y - screen_top.
set_cursor_position:
    ld hl, (cursor_y)
    ld de, (screen_top)
    or a
    sbc hl, de          ; y coord is in l
    inc l               ; adjust because VT100 screen coords start at 1, 
    ld a, (screen_left) ; but we start at 0
    ld b, a
    ld a, (cursor_x)
    sub b               
    ld c, a             ; x coord is in b
    inc c               ; adjust because VT100 screen coords start at 1, 
    ld b, l             ; but we start at 0, y coord now in b
    call move_to_xy
    ret

; Redraw the entire screen. We draw starting at a given set of coords. 
; These are stored in screen_left,screen_top: 0,0 to start at top of doc. 
; 10,0 to start at the top of the doc, but scrolled across 10 chars.
; 0,20 to start on line 21, scrolled to the left.
; We may be showing a selected area, if the selected start loc isn't FFFF.
; The selected area marks a location in the doc to start the selection,
; and a location to stop the selection.
show_screen:	
    ld hl, (doc_start)
    ld bc, (screen_top)
    call skip_lines
    call hide_cursor
    call cls 
    xor a
    ld (shown_lines), a
show_screen_row:
    ld a, (screen_left)
    ld (current_col), a   ; Keep track of current column we are displaying
    call skip_cols
    jr z, shown_enough

show_screen_h1:    
    ld a, (VIEW_WIDTH)              
    ld b, a               ; b = cols left to Show
show_screen1:
    ld a, (hl)
    cp END_OF_TEXT
    jp z, show_screen_done
    cp EOL 
    jr z, show_screen_eol
    cp TAB 
    jr z, show_screen_tab
    bit 7, a                     ; Is bit 7 set?
    jr z, show_screen_simple     ; Skip next bit if not set
    ld c, a
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '3'
    call print_a
    ld a, '2'
    call print_a
    ld a, 'm'
    call print_a

show_screen_simple1:
    ld a, c
show_screen_simple:     
    and 01111111b      ;  Clear bit 7 - was %01111111 -mod for assembler
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    dec b
    jr z, shown_enough
    inc hl
    jr show_screen1
shown_enough:
    call skip_to_start_of_next_line
    dec hl
show_screen_eol:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '0'
    call print_a
    ld a, 'm'
    call print_a
show_screen_eol1:    
    ld a, (screen_left)
    ld (current_col), a                 ; start a new row
    ld a, (shown_lines)
    inc a
    ld (shown_lines), a
    ld e, a
    ld a, (VIEW_HEIGHT)
    ld d, a
    ld a, e
    cp d
    jr nc, show_screen_done
    ld a, 13
    call print_a
    ld a, 10
    call print_a
    inc hl
    jp show_screen_row
show_screen_done:
    call show_cursor
    ret
show_screen_tab:
    push bc
    ld a, (current_col)
    and TAB_MASK
    ld b, a
    ld a, TAB_WIDTH
    sub b
    ld b, a                 ; b stores how long a tab is
show_screen_tab1:
    ld a, ' '               ; show a tab
    call print_a
    ld a, (current_col)
    inc a
    ld (current_col), a
    djnz show_screen_tab1
    inc hl
    pop bc
    jp show_screen1

; We are pointing to the doc in hl.  This skips across "a" cols.
; If a TAB is found we need to take that into account.
; Returns Z if could not skip that number of cols, or NZ if all good.
; Returns the new doc pointer in hl, returns the new cursor_x in c.
skip_cols:
    ld c, 0                         ; c = current col = 0
    or a
    jr z, skip_cols_done            ; return with NZ if no cols to skip
    ld b, a                         ; b = number of cols to skip
skip_col:
    ld a, (hl)
    cp END_OF_TEXT
    ret z                           ; exit with Z if found end of doc
    cp EOL 
    ret z                           ; exit with Z if found end of row
    cp TAB
    jr nz, skip_cols_not_tab
    ld a, c        ; If we are on a tab we need to swallow 1-7 increments
    and TAB_MASK
    ld d, a
    ld a, TAB_WIDTH 
    dec a
    sub d      ; for first char of tab, a=7, 2nd a=6, 3rd a=5, last a=0               
    cp b       ; if b<a then will not reach the end of tab, so stay here
    jr nc, skip_cols_done
    ; take a off of b
    ld d, a
    ld a, b
    sub d
    ld b, a
    ld a, c             ; add a onto c, so we skip that many tabs
    add a, d
    ld c, a
skip_cols_not_tab:
    cp 59 + 128         ;  Tasm error, dec 59 = ';'
    jr nz, skip_cols_not_comment
    ld a, 1
;   ld (comment_mode), a
skip_cols_not_comment:
    inc c                           ; increase col counter
    inc hl                          ; increase doc pointer
    djnz skip_col
skip_cols_done:
    or 1                            ; return NZ
    ret

; We are pointing to the doc in hl.
; This skips along a line and stops when a non-space, non-tab is found
; If a TAB is found we need to take that into account.
; Returns Z if could not skip that number of cols, or NZ if all good.
; Returns the new doc pointer in hl, returns the new cursor_x in c.
skip_spaces:
    ld c, 0                         ; c = current col = 0
skip_space:
    ld a, (hl)
    cp ' '
    jr z, skip_spaces_not_tab
    cp TAB
    jr nz, skip_spaces_done
skip_tab:
    ; If we are on a tab we need to swallow 1-7 increments
    ld a, c
    and TAB_MASK
    ld d, a
    ld a, TAB_WIDTH
    dec a
    sub d      ; for first char of tab, a=7, 2nd a=6,3rd a=5, last a=0
    add a, c
    ld c, a
skip_spaces_not_tab:
    inc c                           ; increase col counter
    inc hl                          ; increase doc pointer
    jr skip_space
skip_spaces_done:
    or 1                            ; return NZ
    ret

; We are pointing to the doc in hl.  This skips down "bc" lines.
skip_lines:
    ld a, b
    or c
    ret z
    call skip_to_start_of_next_line
    dec bc
    jr skip_lines

; Pointing to the doc in hl. This skips to the start of the next line.
skip_to_start_of_next_line:
    push af
skip_a_line_loop
    ld a, (hl)
    cp END_OF_TEXT 
    jr z, skip_a_line2
    inc hl
    cp EOL 
    jr nz, skip_a_line_loop
skip_a_line2:
    pop af
    ret

; Pointing to the doc in hl. This skips to the start of the prev line.
; This means move back until we hit the start of the file, or CR.
; Then skip back again until we hit another CR, or start of file again.
; Then move forward one.
skip_to_start_of_previous_line:
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jr z, found_start
    cp EOL
    jr nz, skip_to_start_of_previous_line  
	
skip_to_start_of_line:    ; Found end of previous line
    dec hl
    ld a, (hl)
    cp START_OF_TEXT
    jr z, found_start
    cp EOL
    jr nz, skip_to_start_of_line
found_start:
    inc hl
    ret

; We are pointing to the start of a line in the doc in hl.
get_line_length:   
    push hl    ; Return in A the length of the line. Preserve hl
    ld b, 1
get_line_length1:
    ld a, (hl)
    cp END_OF_TEXT
    jr z, get_line_length_done
    cp EOL
    jr z, get_line_length_done
    inc hl
    inc b
    jr get_line_length1
get_line_length_done:
    ld a, b
    pop hl
    ret

inc_doc_lines:
    push hl
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl
    pop hl
    ret

clear_keybuff:
    ld hl, keybuff
    ld (keypointer), hl
    ld a, $00
    ld (keybuff), a
    ld (keybuff+1), a
    ld (keybuff+2), a
    ld (keybuff+3), a
    ld (keybuff+4), a
;   ld (keybuff+5), a   ;Reduce keybuf by 4bytes **** -mod ****
;   ld (keybuff+6), a
;   ld (keybuff+7), a
;   ld (keybuff+8), a
    xor a
    ld (keycounter), a
    ret

; Read a key from the keyboard and decide on what it means.
; It can be:
; A normal key press. If so return the ASCII char.
; A cursor key. If so return one of the ACTION values.
; Another special key like delete or enter. Return the ACTION value.
; Return 0 if no user_action.
;
; The key definitions are stored like this:
; DELETE = 05, 23, 47, 90, 22, 33, 44, 55, 00, ACTION
; If they are not 8 keys long they are padded with 00s:
; CURSOR_UP = 12, 65, 00, 00, 00, 00, 00, 00, 00, ACTION
; ENTER = 13, 00, 00, 00, 00, 00, 00, 00, 00, ACTION
; ACTION is the number of the desired action, e.g. CURSOR_UP = 128
; When you press a key, you may get 1 to 8 actual keys from it.
; These are compared to each definition in the table, in turn.
; If more than one match then we need to wait for another key.
; Some keys are not configurable. These are single key presses, 
; and are  >= 32 and < 127. The keys go into a buffer, called keybuff.
; It's 8 spaces long. It has a pointer called
; keypointer, and a counter called keycounter. 
; When we get a good key, we clear the buffer.
get_user_action:
    call get_key_with_timeout    ; c = key
    ld a, (keycounter)
    or a                         ; Are we at the start of the keybuff?
    jr nz, get_user_action1
    ld a, c
    cp 0
    jr z, get_user_action        ; If nothing pressed, start again
    cp ' '	
    jr c, get_user_action1       ; Not ordinary key press if < 32
    cp 127
    jr nc, get_user_action1      ; Not ordinary key press if >= 127	
	ret                          ; Otherwise ordinary key press, like "G"
	
; Have we read a 9th key? If so something is wrong and need to start again.	
get_user_action1:   
    ld a, (keycounter)
    cp 4                         ;was 8, decreased to 4 **** -mod  ****
    jr c, get_user_action2
    call clear_keybuff
    jp get_user_action4
get_user_action2:           ; Is it one of the programmable keys?
    ld hl, (keypointer)     ; hl points to the appropriate place in keybuf
    ld a, c
    ld (hl), a              ; Store the key in the buffer
    inc hl                  ; Increase keypointer
    ld (keypointer), hl
    ld a, (keycounter)
    inc a
    ld (keycounter), a      ; Increase the keycounter
    ld de, keytable         ; Start looking in the keytable for a match
get_user_action3:
    ld a, (de)
    cp $00                  ; Have we run out of possible matches?
    jr z, get_user_action4
    push de                 ; Store de for now
    ld hl, keybuff          ; hl starts at the beginning of the key buffer
    ld b, 4                 ; was 8, now Match 4 keys max **** -mod  ****
get_user_action_loop:
    ld a, (de)
    cp (hl)
    jr nz, get_action_no_match
    inc de
    inc hl
    djnz get_user_action_loop    ; After 8 good matches, we have our action
    call clear_keybuff           ; reset ready for next time
    inc de                       ; de now points to the user action
    ld a, (de)
    pop de                       ; Drain de from stack
    ret                          ; Return the action
get_action_no_match:
    pop de                       ; restore keytable pointer
    inc de
    inc de
    inc de
    inc de
    inc de
;   inc de                       ;reduce by 4 *** -mod ***
;   inc de
;   inc de
;   inc de
    inc de                       ; move to next entry in table
    jr get_user_action3
get_user_action4:
    xor a                        ; Failed to find any matches
    ret

find_address_of_bios:       ; Find address of BIOS
    ld hl, (1)
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CONST
    ld (BIOS_CONST), hl
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CON_IN
    ld (BIOS_CON_IN), hl
    inc hl
    inc hl
    inc hl                  ; hl points to BIOS_CON_OUT
    ld (BIOS_CON_OUT), hl
    ret

JP_HL: jp (hl)

escape_seq:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
	ret 

cursorhome: 
    call escape_seq
    ld a, 'H'
    call print_a
	ret

cleareos: 
    call escape_seq
    ld a, 'J'
    call print_a
	ret	
	
cleareol:
    call escape_seq
	ld a, 'K'
    call print_a
	ret	
	
cls:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 'H'
    call print_a
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, 'J'
    call print_a
    ret

newline:
    ld a, 13
    call print_a
    ld a, 10
    jr print_a

; Prints "a" to the screen
print_a:
    push hl
    push bc
    push de
    ld hl, (BIOS_CON_OUT)
    ld c, a
    call JP_HL
    pop de
    pop bc
    pop hl
    ret

; Reads keyboard into "c"
get_key:
    push hl
    push bc
    push de
    ld hl, (BIOS_CON_IN)
    call JP_HL
    pop de
    pop bc
    pop hl
    ld c, a
    ret

; Checks if there is a key to input. Returns Z if so, NZ if not.
key_ready:
    push hl
    push bc
    push de
    ld hl, (BIOS_CONST)
    call JP_HL
    pop de
    pop bc
    pop hl
    cp $FF
    ret

hide_cursor:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '?'
    call print_a
    ld a, '2'
    call print_a
    ld a, '5'
    call print_a
    ld a, 'l'
    call print_a
    ret

show_cursor:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, '?'
    call print_a
    ld a, '2'
    call print_a
    ld a, '5'
    call print_a
    ld a, 'h'
    call print_a
    ret

; Wait for a key. Return it in C. If it takes too long to arrive, return 0.
get_key_with_timeout:
    ld bc, 2000
get_key_with_timeout_loop:    
    push bc
    call key_ready
    pop bc
    jr z, get_key_with_timeout1
    dec bc
    ld a, b
    or c
    cp 0
    jr nz, get_key_with_timeout_loop
    ld c, 0                    ; Failed to get key, so return 0
    ret
get_key_with_timeout1:
    call get_key
    ret

; Prints a number (in a) from 0 to 255 in decimal
print_a_as_decimal:
    ld c, 0               ; c tells us if we have started printing digits
    ld b, a
    cp 100
    jr c, print_a_as_decimal_tens
    cp 200
    jr c, print_a_as_decimal_100
    ld a, '2'
    call print_a
    ld a, b
    sub 200
    jr print_a_as_decimal_101
print_a_as_decimal_100:
    ld a, '1'
    call print_a
    ld a, b
    sub 100
print_a_as_decimal_101:
    ld c, 1                     ; Yes, we have started printing digits
print_a_as_decimal_tens:
    ld b, 0
print_a_as_decimal_tens1:
    cp 10
    jr c, print_a_as_decimal_units
    sub 10
    inc b
    jr print_a_as_decimal_tens1
print_a_as_decimal_units:
    ld d, a
    ld a, b
    cp 0
    jr nz, print_a_as_decimal_show_tens
    ld a, c
    cp 0
    jr z, print_a_as_decimal_units1
print_a_as_decimal_show_tens:
    add a, '0'
    call print_a
print_a_as_decimal_units1:
    ld a, '0'
    add a, d
    call print_a
    ret

; Pass in x coord in c, y coord in b
; This moves the cursor to the requested location on screen.
move_to_xy:
    ld a, ESC
    call print_a
    ld a, '['
    call print_a
    ld a, b
    push bc
    call print_a_as_decimal
    ld a, 59    ;  Tasm error, dec 59 = ';'
    call print_a
    pop bc
    ld a, c
    call print_a_as_decimal
    ld a, 'H'
    call print_a
    ret

show_string_de:
    ld c, BDOS_Print_String
    call BDOS
    ret

show_a_as_hex:
    push af
    srl a
    srl a
    srl a
    srl a
    add a,'0'
	cp ':'
	jr c, show_a_as_hex1
	add a, 7
show_a_as_hex1:
    call print_a
    pop af
    and 00001111b
    add a,'0'
	cp ':'
	jr c, show_a_as_hex2
	add a, 7
show_a_as_hex2:
    call print_a
    ret

; This puts zeros in the rest of a FCB, for +12 to +35
clear_remainder_of_fcb:
    ld hl, FCB+12
    ld b, 24
clear_remainder_of_fcb1:
    ld (hl), 0
    inc hl
    djnz clear_remainder_of_fcb1
    ret

write_a:
    ld hl, (write_pointer)
    ld (hl), a
    inc hl
    ld (write_pointer), hl
    ret

read_a:
    ld hl, (read_pointer)
    ld a, (hl)
    inc hl
    ld (read_pointer), hl
    ret

; Test if the file can be opened for reading
load_file:
    ld c, BDOS_Open_File
    ld de, FCB
    call BDOS
    inc a
    jp z, could_not_open_file

    ld de, DMA                      ; Use the standard DMA area
    ld c, BDOS_Set_DMA_Address
    call BDOS

; Read in a sector at a time until finished, or out of memory.
; The sector gets read into the standard DMA area.
load_file_loop:
    ld de, FCB
    ld c, BDOS_Read_Sequential
    call BDOS
    cp 0
    jr nz, load_file_done

; Copy 128 bytes of data from DMA area into our internal storage for it.
; Any CR/LF combos are relaced by a single CR.
    ld de, (doc_end)
    ld hl, DMA
    ld b, 128
load_file_loop1:
    ld a, (hl)
    cp TAB
    jr z, load_file_loop_good_char
    cp EOL
    jr z, load_file_loop_eol
    cp 32
    jr c, load_file_loop_bad_char
    cp 127
    jr nc, load_file_loop_bad_char
load_file_loop_good_char:    
    ld (de), a
    inc de
load_file_loop_bad_char:    
    inc hl
    djnz load_file_loop1

    ld (doc_end), de    ; Increase the doc end pointer
    ld hl, (ram_end)    ; If doc end pointer is too near top of memory
    or a                ;    then we are out of mem.   clear carry
    sbc hl, de
    ld a, h
    cp 0
    jr nz, load_file_loop
    ld a, l
    cp 129
    jr nc, load_file_loop
    jr out_of_memory

load_file_loop_eol:
    push hl
    ld hl, (doc_lines)
    inc hl
    ld (doc_lines), hl
    pop hl
    jr load_file_loop_good_char

load_file_done:
    ld de, FCB
    ld c, BDOS_Close_File
    call BDOS
	cp 255                               ; added for debug -mod
	jr nz, file_closed                   ;
    ld de, could_not_close_input         ;
    call show_string_de                  ;

file_closed:	
    ld hl, (doc_end)
    ld (hl), END_OF_TEXT
    ret

out_of_memory:
    ld de, out_of_memory_message
    call show_string_de
	jp exit
	
could_not_open_file:
    ld de, could_not_open_file_message
    call show_string_de
    jp 0
	
out_of_memory_message:
    .db "Out of memory!",13,10,'$'
could_not_close_input:
    .db "Failed to close file",13,10,'$'	
could_not_open_file_message:
    .db "File not found.",13,10,'$'

; turn off any selection
clear_selection:
    ld hl, $ffff
    ld (selection_start), hl
    ld (selection_end), hl
    ret

; clear doc_lines
clear_doc_lines: 
    ld hl, 0
    ld (doc_lines), hl
    ret

show_cursor_coords:
    ld c, 10
    ld b, 25
    call move_to_xy
    ld a, (cursor_x)
    call print_a_as_decimal
    ld a, ' '
    call print_a
    ld a, ' '
    call print_a
    ret    
	
; variables
cursor_x:        .db 0
cursor_y:        .dw 0
want_x:          .db 0 ; The cursor_x value that the user wants to be on, 
                      ; but can't be on it because line is too short.
shown_lines:     .db 0
doc_start:       .dw 0
doc_end:         .dw 0
doc_lines:       .dw 0
need_to_redraw_screen: .db 0
selection_start: .dw 0
selection_end:   .dw 0
screen_top:      .dw 0
screen_left:     .db 0
current_col:     .db 0
doc_pointer:     .dw 0
ram_end:         .dw 0
read_pointer:    .dw 0
write_pointer:   .dw 0
hang_over:       .db 0
all_done:        .db 0
;keybuff         .ds 6 
keybuff          .db 0,0,0,0,0,0   ;fill with 0s -mod for assem **-mod**
keycounter       .db 0
keypointer       .dw 0
BIOS_CONST       .dw 0
BIOS_CON_IN      .dw 0
BIOS_CON_OUT     .dw 0
;stack           .ds 31  ;fill with zeroes for .hex/.com assem compares
stack   .db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 
stacktop         .db 0	
end_of_code      .db 0     ; From here on is free space for the text file

				 .END
