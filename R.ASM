CODE    SEGMENT

	ASSUME CS:CODE, DS:CODE, ES:CODE, SS:CODE
	ORG 100H
index   EQU     03b4h
cntrl   EQU     03b8h

scrn_on EQU     8
grph    EQU     2
text    EQU     20h

MAIN    PROC    NEAR
ep:
	mov dx, 03bfh   
	mov al, 3
	out dx, al
	;port 03bf is page mode setter 4 herc card 0=diag, 1=one page, 3=2 page
	mov al, grph
	mov si, OFFSET gtable
	xor bx, bx
	mov cx, 4000h
	call setmd              ;Set up graphics mode

;       DO DRAWING HERE

	mov ax, 300
	mov bx, 0
	mov cx, 300
	mov dx, 250
	call LINE	

	xor ax, ax
	int 16h
	mov al, text            ;return to text mode
	mov si, OFFSET ttable
	mov bx, 720h
	mov cx, 2000
	call setmd

	mov dx, 03bfh   
	mov al, 0				;return to debug/txt mode
	out dx, al
	mov ax, 4c00h
	int 21h
gtable  db      35h, 2dh, 2eh, 07h
	db      5bh, 02h, 57h, 57h
	db      02h, 03h, 00h, 00h

ttable  db      61h, 50h, 52h, 0fh
	db      19h, 06h, 19h, 19h
	db      02h, 0dh, 0bh, 0ch
MAIN    ENDP

PIXL    PROC    NEAR
;Finds the offset into Page for the pixel to draw
;Input
;ax=pixel x-coordinate (0-719)
;bx=pixel y-coordinate (0-319)
;Returns
;ax=offset into page
;bx (bl)=bitmask for bit at (x,y)
;Saves all other registers
;Equation: [2000h * (y mod 4)] + [90*floor(y/4)] + floor(x/8)]
;Bitmask: 7 - (x mod 8)
;Work backwards by calculating floor first, and storing on stack then popping
;NOTE, AIM TO REMOVE THE MUL/DIV INSTRUCTIONS
	push cx         ;save scratch registers
	push dx
	push ax         ;save ax for bitmask calculation at the end
	mov cx, 3
	shr ax, cl      ;divide by 8, automatically clears upper bits
	push ax         ;store floor(x/8)
	mov ax, bx      ;move y into ax
	dec cx
	shr ax, cl      ;divide by 4
	push ax         ;store floor(y/4)
	cmp ax, 4               ;if y is less than 4...
	jae lp0
	mov ax, bx              ;return the y coordinate to ax
	jmp short lp1

lp0:
	mov cx, 4
	div cl
	xchg al, ah		;modulo 4 in ah
	xor ah, ah
lp1:
	mov cx, 13		;multiply by 2000h (lsh by 13)
	shl ax, cl      ;ax now contains 2000h*(y mod 4)

	mov bx, ax      ;use bx to accumulate the sum
	pop ax          ;retrieve floor(y/4)
	mov cx, 90
	mul cl          ;ax contains al*90 (aka floor(y/4)*90)
	add bx, ax      ;add this result to bx
	pop ax          ;get floor(x/8)
	add bx, ax      ;add ax to bx to save it
	pop ax          ;get the x coordinate into ax
	cmp ax, 8       ;if the x coord is < 8, no divide, it is its own residue
	jb lp2
	mov cx, 8
	div cl          ;divide by 8 (to get remainder, not quotient)[consdr shr]
lp2:
	mov al, 7       ;move value to subtract ah from into al
	sub al, ah      ;subtract the remainder ah from 7, save in al
	xor ah, ah      ;(since we need only 7-(x mod 8), zero upper byte
	;bx contains sum, ax contains bitmask
	xchg bx, ax

	pop dx
	pop cx
	ret
PIXL    ENDP

PSET    PROC    NEAR
;Input: ax=offset into page, bl=bitmask for pixel bit, bh=page (1=page1 0=page0)
	push ds
	push es
	push si
	push di
	push dx


	xor si, si
	dec bh
	jnz pset0
	inc si
pset0:  
	push bx ;temp save bx to use as table base
	mov bx, OFFSET p0
	mov dx, WORD PTR [bx+si]
	pop bx  ;get back bl since we need it now
	mov ds, dx
	mov es, dx
	mov si, ax
	mov di, ax
	lodsb   ;get ds:si into al
	or al, bl       ;set bit
	stosb   ;return al to es:di

	pop dx
	pop di
	pop si
	pop es
	pop ds
	ret
p0      dw      0B000h
p1      dw      0B800h
PSET    ENDP

PCLR    PROC    NEAR
;Input: ax=offset into page, bl=bitmask for pixel bit, bh=page (1=page1 0=page0)
	push ds
	push es
	push si
	push di
	push dx

	xor si, si
	dec bh
	jnz pclr0
	inc si
pclr0:  
	push bx ;temp save bx to use as table base
	mov bx, OFFSET p0
	mov dx, WORD PTR [bx+si]
	pop bx  ;get back bl since we need it now
	mov ds, dx
	mov es, dx
	mov si, ax
	mov di, ax
	lodsb   ;get ds:si into al
	and al, bl       ;set bit
	stosb   ;return al to es:di

	pop dx
	pop di
	pop si
	pop es
	pop ds
	ret
PCLR    ENDP

LINE	PROC	NEAR
;draws a line connecting (x0, y0) to (x1, y1)
;x0=ax, y0=bx, x1=cx, y1=dx, bp=page number (0/1)
;assuming x,y1>x,y0
;0 <= xi <=719, ;0 <= yi <=319,
;Following algorithm:
;plotLine(x0, y0, x1, y1)
;   dx = x1 - x0
;   dy = y1 - y0
;   D = 2*dy - dx
;   y = y0
;   for x from x0 to x1
;       plot(x,y)
;       if D > 0
;           y = y + 1
;           D = D - 2*dx
;       end if
;       D = D + 2*dy

	cmp ax, 720 
	jae lexit
	cmp bx, 320 
	jae lexit
	cmp cx, 720 
	jae lexit
	cmp dx, 320 
	jae lexit

	push cx
	mov cx, 8
	shl bp, cl	;prepare bp to add to bx
	pop cx
;cx will contain the dx and dy values, dx will contain D
;(ax,bx) will be the iterated (x,y) coords
	mov [linex], cx
	sub cx, ax
	mov [lindx], cx
	sub dx, bx
	mov [lindy], dx
	shl dx, 1	
	sub dx, cx
	mov [linD], dx
l0:
;Plot here	
	push ax
	push bx
	call pixl
	add bx, bp
	call pset
	pop bx
	pop ax
;if statement
	cmp dx, 0
	jbe l1	;if D > 0
	inc bx
	mov cx, word ptr [lindx]
	shl cx, 1
	sub dx, cx
l1:
	mov cx, word ptr [lindy]
	shl cx, 1
	add dx, cx
	inc ax
	cmp ax, word ptr [linex]
	jne l0
lexit:
	ret
lindx	dw	0
lindy	dw	0
linD	dw	0
linex	dw	0
LINE	ENDP


SETMD   PROC    NEAR
;set mode to graphics or text
;depending on value in al
;si=parameter table
;cx=number of words to be cleared
;bx=blank value
	push ax
	push bx
	push cx
;change mode with without scrn_on
	mov dx, cntrl
	out dx, al
;initialise the 6845
	mov dx, index
	mov cx, 12
	xor ah, ah
parms:  mov al, ah
	out dx, al
	inc dx
	lodsb
	out dx, al
	inc ah
	dec dx
	loop parms
	pop cx
	mov ax, 0b000h
	cld
	mov es, ax
	xor di, di
	pop ax
	rep stosw
;scrn_on, page 0
	mov dx, cntrl
	pop ax
	add al, scrn_on
	out dx, al
	push ds
	pop es          ;return es back to same segment
	ret     
SETMD   ENDP
CODE    ENDS
	END     MAIN
