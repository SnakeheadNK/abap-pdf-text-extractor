CLASS zcl_pdf_stream DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING
        iv_raw_stream TYPE xstring
        it_filters    TYPE tt_string.

    METHODS get_raw_stream RETURNING VALUE(rv_raw_stream) TYPE xstring.
    METHODS get_filters RETURNING VALUE(rt_filters) TYPE tt_string.

  PRIVATE SECTION.
    DATA mv_raw_stream TYPE xstring.
    DATA mt_filters TYPE tt_string.
ENDCLASS.

CLASS zcl_pdf_stream IMPLEMENTATION.
  METHOD constructor.
    mv_raw_stream = iv_raw_stream.
    mt_filters = it_filters.
  ENDMETHOD.

  METHOD get_raw_stream.
    rv_raw_stream = mv_raw_stream.
  ENDMETHOD.

  METHOD get_filters.
    rt_filters = mt_filters.
  ENDMETHOD.
ENDCLASS.
