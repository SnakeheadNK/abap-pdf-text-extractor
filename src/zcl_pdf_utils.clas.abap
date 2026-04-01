CLASS zcl_pdf_utils DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS xstring_to_string
      IMPORTING
        iv_raw TYPE xstring
      RETURNING
        VALUE(rv_text) TYPE string.

    CLASS-METHODS xstring_to_latin1_string
      IMPORTING
        iv_raw TYPE xstring
      RETURNING
        VALUE(rv_text) TYPE string.

    CLASS-METHODS string_to_xstring
      IMPORTING
        iv_text TYPE string
      RETURNING
        VALUE(rv_raw) TYPE xstring.

    CLASS-METHODS find_last
      IMPORTING
        iv_text    TYPE string
        iv_pattern TYPE string
      RETURNING
        VALUE(rv_pos) TYPE i.
ENDCLASS.

CLASS zcl_pdf_utils IMPLEMENTATION.
  METHOD xstring_to_string.
    DATA(lo_conv) = cl_abap_conv_in_ce=>create( input = iv_raw encoding = 'UTF-8' ignore_cerr = abap_true ).
    lo_conv->read( IMPORTING data = rv_text ).
  ENDMETHOD.

  METHOD xstring_to_latin1_string.
    DATA(lo_conv) = cl_abap_conv_in_ce=>create( input = iv_raw encoding = 'ISO-8859-1' ignore_cerr = abap_false ).
    lo_conv->read( IMPORTING data = rv_text ).
  ENDMETHOD.

  METHOD string_to_xstring.
    DATA(lo_conv) = cl_abap_conv_out_ce=>create( encoding = 'UTF-8' ).
    lo_conv->write( data = iv_text ).
    rv_raw = lo_conv->get_buffer( ).
  ENDMETHOD.

  METHOD find_last.
    DATA lv_offset TYPE i.
    DATA lv_found  TYPE i.

    rv_pos = -1.
    lv_offset = 0.

    WHILE lv_offset < strlen( iv_text ).
      FIND iv_pattern IN SECTION OFFSET lv_offset OF iv_text MATCH OFFSET lv_found.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      rv_pos = lv_found.
      lv_offset = lv_found + 1.
    ENDWHILE.
  ENDMETHOD.
ENDCLASS.
