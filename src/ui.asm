BITS 64


; -----------------------------------------------------------------------------
; ui_init -- Initialize a graphical user interface
;  IN:	Nothing
; OUT:	Nothing
ui_init:
	; Grab screen values from kernel
	mov rcx, screen_lfb_get
	call [b_config]
	mov [VideoBase], rax
	xor eax, eax
	mov rcx, screen_x_get
	call [b_config]
	mov [VideoX], ax
	mov rcx, screen_y_get
	call [b_config]
	mov [VideoY], ax
	mov rcx, screen_ppsl_get
	call [b_config]
	mov [VideoPPSL], eax

	; Calculate screen parameters
	xor eax, eax
	xor ecx, ecx
	mov ax, [VideoX]
	mov cx, [VideoY]
	mul ecx
	mov [Screen_Pixels], eax
	mov ecx, 4
	mul ecx
	mov [Screen_Bytes], eax

	; Calculate font parameters
	xor eax, eax
	xor ecx, ecx
	mov ax, [VideoX]
	mov cl, [font_height]
	mul cx
	mov ecx, 4
	mul ecx
	mov dword [Screen_Row_2], eax
	xor eax, eax
	xor edx, edx
	xor ecx, ecx
	mov ax, [VideoX]
	mov cl, [font_width]
	div cx				; Divide VideoX by font_width
	sub ax, 2			; Subtract 2 for margin
	mov [Screen_Cols], ax
	xor eax, eax
	xor edx, edx
	xor ecx, ecx
	mov ax, [VideoY]
	mov cl, [font_height]
	div cx				; Divide VideoY by font_height
	sub ax, 2			; Subtrack 2 for margin
	mov [Screen_Rows], ax

	call screen_clear

	; Overwrite the kernel b_output function so output goes to the screen instead of the serial port
	mov rax, output_chars
	mov rdi, 0x100018
	stosq

	; Move cursor to bottom of screen
	mov ax, [Screen_Rows]
	dec ax
	mov [Screen_Cursor_Row], ax

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ui_input -- Take string from keyboard entry
;  IN:	RDI = location where string will be stored
;	RCX = maximum number of characters to accept
; OUT:	RCX = length of string that was received (NULL not counted)
;	All other registers preserved
ui_input:
	push rdi
	push rdx			; Counter to keep track of max accepted characters
	push rax

	mov rdx, rcx			; Max chars to accept
	xor ecx, ecx			; Offset from start

ui_input_more:
	mov al, '_'			; Cursor character
	call output_char		; Output the cursor
	call dec_cursor			; Set the cursor back by 1
ui_input_halt:
	hlt				; Halt until an interrupt is received
	call [b_input]			; Returns the character entered. 0 if there was none
	jz ui_input_halt		; If there was no character then halt until an interrupt is received
ui_input_process:
	cmp al, 0x1C			; If Enter key pressed, finish
	je ui_input_done
	cmp al, 0x0E			; Backspace
	je ui_input_backspace
	cmp al, 32			; In ASCII range (32 - 126)?
	jl ui_input_more
	cmp al, 126
	jg ui_input_more
	cmp rcx, rdx			; Check if we have reached the max number of chars
	je ui_input_more		; Jump if we have (should beep as well)
	stosb				; Store AL at RDI and increment RDI by 1
	inc rcx				; Increment the counter
	call output_char		; Display char
	jmp ui_input_more

ui_input_backspace:
	test rcx, rcx			; backspace at the beginning? get a new char
	jz ui_input_more
	mov al, ' '			; 0x20 is the character for a space
	call output_char		; Write over the last typed character with the space
	call dec_cursor			; Decrement the cursor again
	call dec_cursor			; Decrement the cursor
	dec rdi				; go back one in the string
	mov byte [rdi], 0x00		; NULL out the char
	dec rcx				; decrement the counter by one
	jmp ui_input_more

ui_input_done:
	xor al, al
	stosb				; We NULL terminate the string
	mov al, ' '
	call output_char
	call output_newline

	pop rax
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ui_output -- Displays text
;  IN:	RSI = message location (zero-terminated string)
; OUT:	All registers preserved
ui_output:
	push rcx

	call string_length		; Calculate the length of the provided string
	call output_chars		; Output the required number of characters

	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; inc_cursor -- Increment the cursor by one, scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
inc_cursor:
	push rax

	inc word [Screen_Cursor_Col]	; Increment the current cursor column
	mov ax, [Screen_Cursor_Col]
	cmp ax, [Screen_Cols]		; Compare it to the # of columns for the screen
	jne inc_cursor_done		; If not equal we are done
	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	inc word [Screen_Cursor_Row]	; Increment the current cursor row
	mov ax, [Screen_Cursor_Row]
	cmp ax, [Screen_Rows]		; Compare it to the # of rows for the screen
	jne inc_cursor_done		; If not equal we are done
	call screen_scroll		; Otherwise scroll the screen
	dec word [Screen_Cursor_Row]	; Decrement the current cursor row

inc_cursor_done:
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; dec_cursor -- Decrement the cursor by one
;  IN:	Nothing
; OUT:	All registers preserved
dec_cursor:
	push rax

	cmp word [Screen_Cursor_Col], 0
	jne dec_cursor_done
	dec word [Screen_Cursor_Row]
	mov ax, [Screen_Cols]
	mov word [Screen_Cursor_Col], ax

dec_cursor_done:
	dec word [Screen_Cursor_Col]

	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_chars -- Displays text
;  IN:	RSI = message location (an ASCII string, not zero-terminated)
;	RCX = number of chars to print
; OUT:	All registers preserved
output_chars:
	push rdi
	push rsi
	push rcx
	push rax

output_chars_nextchar:
	jrcxz output_chars_done
	dec rcx
	lodsb				; Get char from string and store in AL
	cmp al, 13			; Check if there was a newline character in the string
	je output_chars_newline		; If so then we print a new line
	cmp al, 10			; Check if there was a newline character in the string
	je output_chars_newline		; If so then we print a new line
	cmp al, 9
	je output_chars_tab
	call output_char
	jmp output_chars_nextchar

output_chars_newline:
	mov al, [rsi]
	cmp al, 10
	je output_chars_newline_skip_LF
	call output_newline
	jmp output_chars_nextchar

output_chars_newline_skip_LF:
	test rcx, rcx
	jz output_chars_newline_skip_LF_nosub
	dec rcx

output_chars_newline_skip_LF_nosub:
	inc rsi
	call output_newline
	jmp output_chars_nextchar

output_chars_tab:
	push rcx
	mov ax, [Screen_Cursor_Col]	; Grab the current cursor X value (ex 7)
	mov cx, ax
	add ax, 8			; Add 8 (ex 15)
	shr ax, 3			; Clear lowest 3 bits (ex 8)
	shl ax, 3			; Bug? 'xor al, 7' doesn't work...
	sub ax, cx			; (ex 8 - 7 = 1)
	mov cx, ax
	mov al, ' '

output_chars_tab_next:
	call output_char
	dec cx
	jnz output_chars_tab_next
	pop rcx
	jmp output_chars_nextchar

output_chars_done:
	pop rax
	pop rcx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_char -- Displays a char
;  IN:	AL  = char to display
; OUT:	All registers preserved
output_char:
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	call glyph
	call inc_cursor

	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; output_newline -- Reset cursor to start of next line and scroll if needed
;  IN:	Nothing
; OUT:	All registers preserved
output_newline:
	push rax

	mov word [Screen_Cursor_Col], 0	; Reset column to 0
	mov ax, [Screen_Rows]		; Grab max rows on screen
	dec ax				; and subtract 1
	cmp ax, [Screen_Cursor_Row]	; Is the cursor already on the bottom row?
	je output_newline_scroll	; If so, then scroll
	inc word [Screen_Cursor_Row]	; If not, increment the cursor to next row
	jmp output_newline_done

output_newline_scroll:
	call screen_scroll

output_newline_done:
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; glyph_put -- Put a glyph on the screen at the cursor location
;  IN:	AL  = char to display
; OUT:	All registers preserved
glyph:
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push rax

	and eax, 0x000000FF
	cmp al, 0x20
	jl hidden
	cmp al, 127
	jg hidden
	sub rax, 0x20
	jmp load_char
hidden:
	mov al, 0
load_char:

	mov ecx, 12			; Font height
	mul ecx
	mov rsi, font_data
	add rsi, rax			; add offset to correct glyph

; Calculate pixel co-ordinates for character
	xor ebx, ebx
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Row]
	add ax, 1
	mov cx, 12			; Font height
	mul cx
	mov bx, ax
	shl ebx, 16
	xor edx, edx
	xor eax, eax
	mov ax, [Screen_Cursor_Col]
	add ax, 1
	mov cx, 6			; Font width
	mul cx
	mov bx, ax

	xor eax, eax
	xor ecx, ecx			; x counter
	xor edx, edx			; y counter

glyph_nextline:
	lodsb				; Load a line

glyph_nextpixel:
	cmp ecx, 6			; Font width
	je glyph_bailout		; Glyph row complete
	rol al, 1
	bt ax, 0
	jc glyph_pixel
	push rax
	mov eax, [BG_Color]
	call pixel
	pop rax
	jmp glyph_skip

glyph_pixel:
	push rax
	mov eax, [FG_Color]
	call pixel
	pop rax

glyph_skip:
	inc ebx
	inc ecx
	jmp glyph_nextpixel

glyph_bailout:
	xor ecx, ecx
	sub ebx, 6			; column start
	add ebx, 0x00010000		; next row
	inc edx
	cmp edx, 12			; Font height
	jne glyph_nextline

glyph_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; pixel -- Put a pixel on the screen
;  IN:	EBX = Packed X & Y coordinates (YYYYXXXX)
;	EAX = Pixel Details (AARRGGBB)
; OUT:	All registers preserved
pixel:
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	; Calculate offset in video memory and store pixel
	push rax			; Save the pixel details
	mov rax, rbx
	shr eax, 16			; Isolate Y co-ordinate
	xor ecx, ecx
	mov cx, [VideoPPSL]
	mul ecx				; Multiply Y by VideoPPSL
	and ebx, 0x0000FFFF		; Isolate X co-ordinate
	add eax, ebx			; Add X
	mov rbx, rax			; Save the offset to RBX
	mov rdi, [VideoBase]		; Store the pixel to video memory
	pop rax				; Restore pixel details
	shl ebx, 2			; Quickly multiply by 4
	add rdi, rbx			; Add offset in video memory
	stosd				; Output pixel to video memory

	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; scroll_screen -- Scrolls the screen up by one line
;  IN:	Nothing
; OUT:	All registers preserved
screen_scroll:
	push rsi
	push rdi
	push rcx
	push rax

	xor eax, eax			; Calculate offset to bottom row
	xor ecx, ecx
	mov ax, [VideoX]
	mov cl, [font_height]
	mul ecx				; EAX = EAX * ECX
	shl eax, 2			; Quick multiply by 4 for 32-bit colour depth

	mov rdi, [VideoBase]
	mov esi, [Screen_Row_2]
	add rsi, rdi
	mov ecx, [Screen_Bytes]
	sub ecx, eax			; Subtract the offset
	shr ecx, 2			; Quick divide by 4
	rep movsd

	pop rax
	pop rcx
	pop rdi
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; screen_clear -- Clear the screen
;  IN:	Nothing
; OUT:	All registers preserved
screen_clear:
	push rdi
	push rcx
	push rax

	mov rdi, [VideoBase]
	mov eax, [BG_Color]
	mov ecx, [Screen_Bytes]
	shr ecx, 2			; Quick divide by 4
	rep stosd

	pop rax
	pop rcx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; string_length -- Return length of a string
;  IN:	RSI = string location
; OUT:	RCX = length (not including the NULL terminator)
;	All other registers preserved
string_length:
	push rdi
	push rax

	xor ecx, ecx
	xor eax, eax
	mov rdi, rsi
	not rcx
	repne scasb			; compare byte at RDI to value in AL
	not rcx
	dec rcx

	pop rax
	pop rdi
	ret
; -----------------------------------------------------------------------------


%include 'font.inc'

; Variables
align 16

VideoBase:		dq 0
FG_Color:		dd 0x00FFFFFF
BG_Color:		dd 0x00404040
Screen_Pixels:		dd 0
Screen_Bytes:		dd 0
Screen_Row_2:		dd 0
VideoPPSL:		dd 0
VideoX:			dw 0
VideoY:			dw 0
Screen_Rows:		dw 0
Screen_Cols:		dw 0
Screen_Cursor_Row:	dw 0
Screen_Cursor_Col:	dw 0


; =============================================================================
; EOF
