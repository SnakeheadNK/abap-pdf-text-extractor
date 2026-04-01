CLASS zcl_pdf_text_extractor DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

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
    DATA lt_lines TYPE tt_string.
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
    DATA lt_matches TYPE match_result_tab.

    FIND ALL OCCURRENCES OF REGEX '\([^\)]*\)|<[0-9A-Fa-f[:space:]]+>' IN iv_line RESULTS lt_matches.

    LOOP AT lt_matches INTO DATA(ls_match).
      IF ls_match-length <= 0.
        CONTINUE.
      ENDIF.

      DATA lv_literal TYPE string.
      lv_literal = iv_line+ls_match-offset(ls_match-length).

      rv_text = rv_text && io_font_decoder->decode_text_operand(
        iv_pdf_string = lv_literal
        iv_font_name  = iv_font_name ).
    ENDLOOP.
  ENDMETHOD.

  METHOD extract_font_from_tf.
    FIND FIRST OCCURRENCE OF REGEX '/([^ ]+) +[0-9\.]+ +Tf' IN iv_line SUBMATCHES rv_font_name.
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
