CLASS zcx_pdf_error DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS constructor
      IMPORTING
        iv_message TYPE string
        previous   TYPE REF TO cx_root OPTIONAL.

    METHODS get_text REDEFINITION.

  PRIVATE SECTION.
    DATA mv_message TYPE string.
ENDCLASS.


CLASS zcx_pdf_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( previous = previous ).
    mv_message = iv_message.
  ENDMETHOD.

  METHOD get_text.
    result = mv_message.
  ENDMETHOD.
ENDCLASS.
