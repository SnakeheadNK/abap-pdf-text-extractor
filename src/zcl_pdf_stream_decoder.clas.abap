CLASS zcl_pdf_stream_decoder DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    METHODS decode
      IMPORTING
        iv_stream  TYPE xstring
        it_filters TYPE tt_string
      RETURNING
        VALUE(rv_decoded) TYPE xstring
      RAISING
        zcx_pdf_error.

  PRIVATE SECTION.
    METHODS decode_flate
      IMPORTING
        iv_stream TYPE xstring
      RETURNING
        VALUE(rv_decoded) TYPE xstring
      RAISING
        zcx_pdf_error.
ENDCLASS.

CLASS zcl_pdf_stream_decoder IMPLEMENTATION.
  METHOD decode.
    rv_decoded = iv_stream.

    LOOP AT it_filters INTO DATA(lv_filter).
      CASE lv_filter.
        WHEN '/FlateDecode' OR 'FlateDecode'.
          rv_decoded = decode_flate( rv_decoded ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_pdf_error
            EXPORTING iv_message = |Unsupported stream filter: { lv_filter }|.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD decode_flate.
    CALL FUNCTION 'SCMS_XSTRING_DECOMPRESS'
      EXPORTING
        compressed = iv_stream
      IMPORTING
        uncompressed = rv_decoded
      EXCEPTIONS
        failed = 1
        OTHERS = 2.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = 'FlateDecode decompression failed'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_stream_decoder DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS should_raise_for_unknown_filter FOR TESTING.
ENDCLASS.

CLASS ltcl_stream_decoder IMPLEMENTATION.
  METHOD should_raise_for_unknown_filter.
    DATA(lo_decoder) = NEW zcl_pdf_stream_decoder( ).
    TRY.
        lo_decoder->decode( iv_stream = '0102' it_filters = VALUE #( ( 'Unsupported' ) ) ).
        cl_abap_unit_assert=>fail( 'Exception expected' ).
      CATCH zcx_pdf_error.
        cl_abap_unit_assert=>assert_true( abap_true ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
