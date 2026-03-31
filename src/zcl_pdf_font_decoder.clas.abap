CLASS zcl_pdf_font_decoder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_cmap,
             src TYPE string,
             dst TYPE string,
           END OF ty_cmap,
           tt_cmap TYPE HASHED TABLE OF ty_cmap WITH UNIQUE KEY src.

    METHODS register_tounicode_map
      IMPORTING
        iv_font_name TYPE string
        it_map       TYPE tt_cmap.

    METHODS decode_text_operand
      IMPORTING
        iv_pdf_string TYPE string
        iv_font_name  TYPE string
      RETURNING
        VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_font_map,
             font_name TYPE string,
             map       TYPE tt_cmap,
           END OF ty_font_map.
    DATA mt_font_maps TYPE HASHED TABLE OF ty_font_map WITH UNIQUE KEY font_name.

    METHODS decode_literal_string
      IMPORTING iv_pdf_string TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    METHODS decode_hex_string
      IMPORTING iv_pdf_string TYPE string
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS zcl_pdf_font_decoder IMPLEMENTATION.
  METHOD register_tounicode_map.
    DELETE mt_font_maps WHERE font_name = iv_font_name.
    INSERT VALUE ty_font_map( font_name = iv_font_name map = it_map ) INTO TABLE mt_font_maps.
  ENDMETHOD.

  METHOD decode_text_operand.
    IF iv_pdf_string CP '<*>' AND iv_pdf_string NP '(*'.
      rv_text = decode_hex_string( iv_pdf_string ).
    ELSE.
      rv_text = decode_literal_string( iv_pdf_string ).
    ENDIF.

    READ TABLE mt_font_maps WITH KEY font_name = iv_font_name INTO DATA(ls_font_map).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_mapped TYPE string.
    DO strlen( rv_text ) TIMES.
      DATA(lv_char) = rv_text+sy-index-1(1).
      READ TABLE ls_font_map-map WITH KEY src = lv_char INTO DATA(ls_map).
      IF sy-subrc = 0.
        lv_mapped = lv_mapped && ls_map-dst.
      ELSE.
        lv_mapped = lv_mapped && lv_char.
      ENDIF.
    ENDDO.
    rv_text = lv_mapped.
  ENDMETHOD.

  METHOD decode_literal_string.
    DATA lv_input TYPE string.
    DATA lv_len TYPE i.
    DATA lv_idx TYPE i VALUE 0.

    lv_input = iv_pdf_string.
    IF lv_input CP '(*'.
      SHIFT lv_input LEFT DELETING LEADING '('.
      SHIFT lv_input RIGHT DELETING TRAILING ')'.
    ENDIF.

    lv_len = strlen( lv_input ).
    WHILE lv_idx < lv_len.
      DATA(lv_char) = lv_input+lv_idx(1).
      IF lv_char <> '\\'.
        rv_text = rv_text && lv_char.
        lv_idx = lv_idx + 1.
        CONTINUE.
      ENDIF.

      IF lv_idx + 1 >= lv_len.
        EXIT.
      ENDIF.

      DATA(lv_esc) = lv_input+lv_idx+1(1).
      CASE lv_esc.
        WHEN 'n'.
          rv_text = rv_text && cl_abap_char_utilities=>newline.
          lv_idx = lv_idx + 2.
        WHEN 'r'.
          rv_text = rv_text && cl_abap_char_utilities=>cr_lf.
          lv_idx = lv_idx + 2.
        WHEN 't'.
          rv_text = rv_text && cl_abap_char_utilities=>horizontal_tab.
          lv_idx = lv_idx + 2.
        WHEN 'b' OR 'f'.
          lv_idx = lv_idx + 2.
        WHEN '\\' OR '(' OR ')'.
          rv_text = rv_text && lv_esc.
          lv_idx = lv_idx + 2.
        WHEN OTHERS.
          IF lv_esc CO '01234567'.
            DATA(lv_oct) = lv_esc.
            DATA(lv_take) = 1.
            WHILE lv_take < 3 AND lv_idx + 1 + lv_take < lv_len AND lv_input+lv_idx+1+lv_take(1) CO '01234567'.
              lv_oct = lv_oct && lv_input+lv_idx+1+lv_take(1).
              lv_take = lv_take + 1.
            ENDWHILE.

            DATA(lv_code) TYPE i.
            DATA lv_byte TYPE x LENGTH 1.
            DATA lv_byte_x TYPE xstring.
            lv_code = lv_oct.
            lv_byte = lv_code.
            lv_byte_x = lv_byte.
            rv_text = rv_text && zcl_pdf_utils=>xstring_to_string( lv_byte_x ).
            lv_idx = lv_idx + 1 + lv_take.
          ELSE.
            rv_text = rv_text && lv_esc.
            lv_idx = lv_idx + 2.
          ENDIF.
      ENDCASE.
    ENDWHILE.
  ENDMETHOD.

  METHOD decode_hex_string.
    DATA lv_hex TYPE string.
    DATA lv_raw TYPE xstring.

    lv_hex = iv_pdf_string.
    SHIFT lv_hex LEFT DELETING LEADING '<'.
    SHIFT lv_hex RIGHT DELETING TRAILING '>'.
    CONDENSE lv_hex NO-GAPS.

    IF strlen( lv_hex ) MOD 2 = 1.
      lv_hex = lv_hex && '0'.
    ENDIF.

    lv_raw = lv_hex.
    rv_text = zcl_pdf_utils=>xstring_to_string( lv_raw ).
  ENDMETHOD.
ENDCLASS.
