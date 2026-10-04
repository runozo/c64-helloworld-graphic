; =====================================================================
;  graphic.asm  -  "HELLO, WORLD!" in MODALITA' GRAFICA (bitmap hires)
; ---------------------------------------------------------------------
;  CPU      : MOS 6510
;  Assembler: ACME
;  Output   : graphic.prg
;
;  A differenza della versione testo (che usa la KERNAL CHROUT per
;  stampare caratteri nella video-RAM), qui NON esiste alcun carattere:
;  il testo viene DISEGNATO come pixel in un bitmap 320x200.
;
;  Modalita' video: standard bitmap (hires) del VIC-II
;    - bitmap      : $2000-$3FFF  (8000 byte, 1 bit = 1 pixel)
;    - video matrix: $0400-$07E7  (40x25 byte, colore per ogni cella 8x8)
;    - $D018 = $18  -> matrix $0400, bitmap $2000
;    - $D011 = $3B  -> BMM=1 (bitmap), DEN=1, yscroll=3, 25 righe
;    - $D016 = $08  -> MCM=0 (hires), 40 colonne, xscroll=0
;
;  In bitmap mode il byte della video matrix di ogni cella 8x8 seleziona
;  i colori: nibble ALTO = pixel a 1, nibble BASSO = pixel a 0.
;  Usiamo $16 = bianco (1) su blu (6).
; =====================================================================

!cpu 6510
!to "graphic.prg", cbm

; ---------------------------------------------------------------------
;  Indirizzi hardware
; ---------------------------------------------------------------------
BITMAP     = $2000            ; base del bitmap hires
SCREEN     = $0400            ; video matrix (40x25)

VIC_BORDER = $d020
VIC_BG     = $d021
VIC_CTRL1  = $d011
VIC_CTRL2  = $d016
VIC_MEM    = $d018

; ---------------------------------------------------------------------
;  Variabili in zero page (usiamo SEI, quindi la zero page e' libera)
; ---------------------------------------------------------------------
zp_src   = $fb                ; puntatore al glifo (sorgente)
zp_dst   = $fd                ; puntatore alla cella nel bitmap (destinazione)
zp_idx   = $f7                ; indice nella tabella del messaggio

; ---------------------------------------------------------------------
;  BASIC stub: 10 SYS 2061 -> codice a $080D
; ---------------------------------------------------------------------
* = $0801
        !byte $0b, $08, $0a, $00, $9e
        !byte $32, $30, $36, $31
        !byte $00, $00, $00

; ---------------------------------------------------------------------
;  CODICE
; ---------------------------------------------------------------------
* = $080d
start:
        sei                   ; ferma IRQ: schermo statico e zero page libera
        lda #$06
        sta VIC_BORDER        ; bordo blu
        sta VIC_BG            ; sfondo blu (in bitmap non usato, per coerenza)

        jsr clear_bitmap      ; bitmap tutto a 0 (nessun pixel acceso)
        jsr fill_screen       ; video matrix a $16 = bianco su blu
        jsr draw_text         ; disegna i glifi nel bitmap

        lda #$3b              ; abilita la modalita' bitmap
        sta VIC_CTRL1
        lda #$08              ; hires, 40 colonne
        sta VIC_CTRL2
        lda #$18              ; matrix $0400 + bitmap $2000
        sta VIC_MEM

hold:
        jmp hold              ; resta in modalita' grafica

; ---------------------------------------------------------------------
;  clear_bitmap: azzera $2000-$3FFF (32 pagine = 8192 byte)
; ---------------------------------------------------------------------
clear_bitmap:
        lda #$00
        sta zp_dst
        lda #$20
        sta zp_dst+1
        ldy #$00
        tya                   ; A = 0
        ldx #$20              ; 32 pagine
cb_loop:
        sta (zp_dst),y
        iny
        bne cb_loop
        inc zp_dst+1
        dex
        bne cb_loop
        rts

; ---------------------------------------------------------------------
;  fill_screen: riempe la video matrix ($0400-$07FF) con $16
; ---------------------------------------------------------------------
fill_screen:
        lda #$16              ; nibble alto 1 (bianco), basso 6 (blu)
        ldx #$00
fs_loop:
        sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne fs_loop
        rts

; ---------------------------------------------------------------------
;  draw_text: per ogni glifo del messaggio copia 8 byte nel bitmap.
;
;  Il bitmap e' organizzato per celle 8x8: le 8 righe di pixel di una
;  cella sono CONTIGUE (8 byte), e le celle sono nell'ordine della
;  video matrix: cella (riga, col) = base + riga*320 + col*8.
;  Dopo ogni glifo si avanza quindi zp_dst di 8 byte.
; ---------------------------------------------------------------------
draw_text:
        lda #<text_base
        sta zp_dst
        lda #>text_base
        sta zp_dst+1
        lda #$00
        sta zp_idx
dt_loop:
        ldx zp_idx
        lda message,x         ; byte basso del puntatore al glifo
        sta zp_src
        lda message+1,x       ; byte alto
        sta zp_src+1
        ora zp_src            ; se entrambi 0 -> fine tabella
        beq dt_done

        jsr draw_glyph        ; copia gli 8 byte del glifo

        lda zp_dst            ; cella successiva = base + 8
        clc
        adc #$08
        sta zp_dst
        bcc dt_skip
        inc zp_dst+1
dt_skip:
        lda zp_idx            ; indice +2 (puntatori a 16 bit)
        clc
        adc #$02
        sta zp_idx
        jmp dt_loop
dt_done:
        rts

; ---------------------------------------------------------------------
;  draw_glyph: copia un glifo 8x8 da (zp_src) a (zp_dst), 8 byte
; ---------------------------------------------------------------------
draw_glyph:
        ldy #$00
dg_loop:
        lda (zp_src),y        ; riga Y del glifo
        sta (zp_dst),y        ; riga Y della cella nel bitmap
        iny
        cpy #$08
        bne dg_loop
        rts

; ---------------------------------------------------------------------
;  Posizione del testo nel bitmap: riga 12, colonna 13 (centrato)
;  indirizzo = $2000 + 12*320 + 13*8 = $2F68
; ---------------------------------------------------------------------
TEXT_ROW = 12
TEXT_COL = 13
text_base = BITMAP + TEXT_ROW*320 + TEXT_COL*8

; ---------------------------------------------------------------------
;  Tabella del messaggio: "HELLO, WORLD!"
;  Sequenza di puntatori (16 bit) ai glifi, terminata da una word 0.
; ---------------------------------------------------------------------
message:
        !word glyph_H, glyph_E, glyph_L, glyph_L, glyph_O
        !word glyph_COMMA, glyph_SPACE
        !word glyph_W, glyph_O, glyph_R, glyph_L, glyph_D
        !word glyph_EXCL
        !word $0000

; ---------------------------------------------------------------------
;  Font 8x8 disegnato a mano (bit 7 = pixel piu' a sinistra)
; ---------------------------------------------------------------------
glyph_SPACE:
        !byte $00,$00,$00,$00,$00,$00,$00,$00
glyph_EXCL:
        !byte $18,$18,$18,$18,$18,$00,$18,$00
glyph_COMMA:
        !byte $00,$00,$00,$00,$00,$18,$18,$30
glyph_H:
        !byte $81,$81,$81,$ff,$81,$81,$81,$00
glyph_E:
        !byte $ff,$80,$80,$fe,$80,$80,$ff,$00
glyph_L:
        !byte $80,$80,$80,$80,$80,$80,$ff,$00
glyph_O:
        !byte $7e,$81,$81,$81,$81,$81,$7e,$00
glyph_W:
        !byte $81,$81,$81,$a5,$a5,$db,$99,$00
glyph_R:
        !byte $fe,$81,$81,$fe,$90,$88,$84,$00
glyph_D:
        !byte $fc,$82,$81,$81,$81,$82,$fc,$00
