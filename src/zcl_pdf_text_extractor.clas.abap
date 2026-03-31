CLASS zcl_pdf_text_extractor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS extract_text
      IMPORTING
        iv_content_stream TYPE xstring
        io_font_decoder   TYPE REF TO zcl_pdf_font_decoder
      RETURNING
        VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    METHODS extract_text_operands
      IMPORTING
        iv_line         TYPE string
        iv_font_name    TYPE string
        io_font_decoder TYPE REF TO zcl_pdf_font_decoder
      RETURNING
        VALUE(rv_text)  TYPE string.

    METHODS extract_font_from_tf
      IMPORTING
        iv_line TYPE string
      RETURNING
        VALUE(rv_font_name) TYPE string.
ENDCLASS.

CLASS zcl_pdf_text_extractor IMPLEMENTATION.
  METHOD extract_text.
    DATA(lv_content) = zcl_pdf_utils=>xstring_to_string( iv_content_stream ).
    DATA lt_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_in_text_block TYPE abap_bool VALUE abap_false.
    DATA lv_current_font TYPE string VALUE 'DEFAULT'.

    SPLIT lv_content AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    IF lt_lines IS INITIAL.
      APPEND lv_content TO lt_lines.
    ENDIF.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_work_line) = lv_line.

      IF lv_work_line CS 'BT'.
        lv_in_text_block = abap_true.
      ENDIF.

      IF lv_work_line CS 'Tf'.
        DATA(lv_font) = extract_font_from_tf( lv_work_line ).
        IF lv_font IS NOT INITIAL.
          lv_current_font = lv_font.
        ENDIF.
      ENDIF.

      IF lv_in_text_block = abap_true AND ( lv_work_line CS ' Tj' OR lv_work_line CS ' TJ' ).
        rv_text = rv_text && extract_text_operands(
          iv_line         = lv_work_line
          iv_font_name    = lv_current_font
          io_font_decoder = io_font_decoder ).
      ENDIF.

      IF lv_work_line CS 'ET'.
        lv_in_text_block = abap_false.
        rv_text = rv_text && cl_abap_char_utilities=>newline.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD extract_text_operands.
    DATA lv_offset TYPE i VALUE 0.
    DATA lv_len TYPE i.

    lv_len = strlen( iv_line ).
    WHILE lv_offset < lv_len.
      FIND FIRST OCCURRENCE OF '(' IN SECTION OFFSET lv_offset OF iv_line MATCH OFFSET DATA(lv_pos_paren).
      DATA(lv_has_paren) = xsdbool( sy-subrc = 0 ).
      FIND FIRST OCCURRENCE OF '<' IN SECTION OFFSET lv_offset OF iv_line MATCH OFFSET DATA(lv_pos_hex).
      DATA(lv_has_hex) = xsdbool( sy-subrc = 0 ).

      IF lv_has_paren = abap_false AND lv_has_hex = abap_false.
        EXIT.
      ENDIF.

      DATA(lv_start) TYPE i.
      DATA(lv_is_hex) TYPE abap_bool VALUE abap_false.
      IF lv_has_paren = abap_true AND ( lv_has_hex = abap_false OR lv_pos_paren <= lv_pos_hex ).
        lv_start = lv_pos_paren + lv_offset.
      ELSE.
        lv_start = lv_pos_hex + lv_offset.
        lv_is_hex = abap_true.
      ENDIF.

      DATA lv_end_rel TYPE i.
      IF lv_is_hex = abap_true.
        FIND FIRST OCCURRENCE OF '>' IN SECTION OFFSET ( lv_start + 1 ) OF iv_line MATCH OFFSET lv_end_rel.
      ELSE.
        FIND FIRST OCCURRENCE OF ')' IN SECTION OFFSET ( lv_start + 1 ) OF iv_line MATCH OFFSET lv_end_rel.
      ENDIF.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA(lv_end) = lv_end_rel + lv_start + 1.
      DATA(lv_literal) = iv_line+lv_start(lv_end-lv_start+1).

      rv_text = rv_text && io_font_decoder->decode_text_operand(
        iv_pdf_string = lv_literal
        iv_font_name  = iv_font_name ).

      lv_offset = lv_end + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD extract_font_from_tf.
    DATA lt_parts TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    DATA lv_prev TYPE string.

    SPLIT iv_line AT space INTO TABLE lt_parts.
    LOOP AT lt_parts INTO DATA(lv_token).
      IF lv_token = 'Tf'.
        rv_font_name = lv_prev.
        IF rv_font_name CS '/'.
          SHIFT rv_font_name LEFT DELETING LEADING '/'.
        ENDIF.
        RETURN.
      ENDIF.
      IF lv_token IS NOT INITIAL.
        lv_prev = lv_token.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_text_extractor DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS should_extract_tj_and_tj FOR TESTING.
    METHODS should_extract_when_bt_tj_et_in_single_line FOR TESTING.
    METHODS should_extract_hex_tj_and_font_from_tf FOR TESTING.
ENDCLASS.

CLASS ltcl_text_extractor IMPLEMENTATION.
  METHOD should_extract_tj_and_tj.
    DATA(lv_stream_txt) = |BT{ cl_abap_char_utilities=>newline }(Hello) Tj{ cl_abap_char_utilities=>newline }[( ) 10 (World)] TJ{ cl_abap_char_utilities=>newline }ET|.
    DATA(lo_font) = NEW zcl_pdf_font_decoder( ).
    DATA(lo_ext) = NEW zcl_pdf_text_extractor( ).

    DATA(lv_result) = lo_ext->extract_text(
      iv_content_stream = zcl_pdf_utils=>string_to_xstring( lv_stream_txt )
      io_font_decoder   = lo_font ).

    cl_abap_unit_assert=>assert_true( xsdbool( lv_result CS 'Hello' ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lv_result CS 'World' ) ).
  ENDMETHOD.

  METHOD should_extract_when_bt_tj_et_in_single_line.
    DATA(lv_stream_txt) = |BT (One)(Two) Tj ET|.
    DATA(lo_font) = NEW zcl_pdf_font_decoder( ).
    DATA(lo_ext) = NEW zcl_pdf_text_extractor( ).

    DATA(lv_result) = lo_ext->extract_text(
      iv_content_stream = zcl_pdf_utils=>string_to_xstring( lv_stream_txt )
      io_font_decoder   = lo_font ).

    cl_abap_unit_assert=>assert_true( xsdbool( lv_result CS 'One' ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( lv_result CS 'Two' ) ).
  ENDMETHOD.

  METHOD should_extract_hex_tj_and_font_from_tf.
    DATA(lv_stream_txt) = |BT /F1 12 Tf <48656C6C6F> Tj ET|.
    DATA(lo_font) = NEW zcl_pdf_font_decoder( ).
    DATA(lo_ext) = NEW zcl_pdf_text_extractor( ).

    DATA(lv_result) = lo_ext->extract_text(
      iv_content_stream = zcl_pdf_utils=>string_to_xstring( lv_stream_txt )
      io_font_decoder   = lo_font ).

    cl_abap_unit_assert=>assert_true( xsdbool( lv_result CS 'Hello' ) ).
  ENDMETHOD.
ENDCLASS.
