CLASS zcl_pdf_parser DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_ref,
             obj_id     TYPE i,
             generation TYPE i,
           END OF ty_ref,
           tt_object_ref TYPE STANDARD TABLE OF REF TO zcl_pdf_object WITH EMPTY KEY.

    METHODS parse
      IMPORTING
        iv_pdf_raw TYPE xstring
      RAISING
        zcx_pdf_error.

    METHODS parse_all_objects
      RAISING
        zcx_pdf_error.

    METHODS get_object
      IMPORTING
        iv_obj_id TYPE i
      RETURNING
        VALUE(ro_object) TYPE REF TO zcl_pdf_object
      RAISING
        zcx_pdf_error.

    METHODS get_trailer_value
      IMPORTING
        iv_key TYPE string
      RETURNING
        VALUE(rv_value) TYPE string.

    METHODS get_objects
      RETURNING
        VALUE(rt_objects) TYPE tt_object_ref.

  PRIVATE SECTION.
    DATA mv_pdf_text TYPE string.
    DATA mv_startxref TYPE i.
    DATA mo_xref TYPE REF TO zcl_pdf_xref.
    DATA mt_objects TYPE tt_object_ref.
    DATA mt_trailer TYPE zcl_pdf_object=>tt_dict_item.

    METHODS find_startxref RAISING zcx_pdf_error.
    METHODS parse_trailer RAISING zcx_pdf_error.
ENDCLASS.

CLASS zcl_pdf_parser IMPLEMENTATION.
  METHOD parse.
    mv_pdf_text = zcl_pdf_utils=>xstring_to_string( iv_pdf_raw ).

    IF mv_pdf_text NP '%PDF-*'.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = 'Invalid PDF header'.
    ENDIF.

    find_startxref( ).
    mo_xref = NEW zcl_pdf_xref( ).
    mo_xref->read_xref_table( iv_pdf_text = mv_pdf_text iv_startxref = mv_startxref ).
    parse_trailer( ).
    parse_all_objects( ).
  ENDMETHOD.

  METHOD find_startxref.
    DATA(lv_pos) = zcl_pdf_utils=>find_last( iv_text = mv_pdf_text iv_pattern = 'startxref' ).
    IF lv_pos < 0.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = 'startxref not found'.
    ENDIF.

    DATA lv_tail TYPE string.
    lv_tail = mv_pdf_text+lv_pos.
    SPLIT lv_tail AT cl_abap_char_utilities=>newline INTO DATA(lv_kw) DATA(lv_offset_s) DATA(lv_dummy).
    CONDENSE lv_offset_s.
    mv_startxref = lv_offset_s.
  ENDMETHOD.

  METHOD parse_trailer.
    DATA lv_trailer_pos TYPE i.
    FIND FIRST OCCURRENCE OF 'trailer' IN SECTION OFFSET mv_startxref OF mv_pdf_text MATCH OFFSET lv_trailer_pos.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA(lv_text) = mv_pdf_text+mv_startxref+lv_trailer_pos.
    DATA lv_dict_start TYPE i.
    DATA lv_dict_end TYPE i.
    FIND FIRST OCCURRENCE OF '<<' IN lv_text MATCH OFFSET lv_dict_start.
    FIND FIRST OCCURRENCE OF '>>' IN lv_text MATCH OFFSET lv_dict_end.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    DATA lv_dict_len TYPE i.
    DATA lv_dict_raw TYPE string.
    lv_dict_len = lv_dict_end - lv_dict_start + 2.
    lv_dict_raw = lv_text+lv_dict_start(lv_dict_len).
    DATA(lo_trailer_obj) = NEW zcl_pdf_object( iv_id = 0 iv_generation = 0 iv_raw = lv_dict_raw ).
    mt_trailer = lo_trailer_obj->get_dictionary( ).
  ENDMETHOD.

  METHOD parse_all_objects.
    CLEAR mt_objects.

    DATA lv_pos TYPE i.
    lv_pos = 0.
    WHILE lv_pos < strlen( mv_pdf_text ).
      FIND FIRST OCCURRENCE OF REGEX '(\d+)\s+(\d+)\s+obj' IN SECTION OFFSET lv_pos OF mv_pdf_text MATCH OFFSET DATA(lv_obj_pos) MATCH LENGTH DATA(lv_obj_len) SUBMATCHES DATA(lv_id_s) DATA(lv_gen_s).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_obj_pos = lv_obj_pos + lv_pos.

      DATA lv_endobj_pos TYPE i.
      FIND FIRST OCCURRENCE OF 'endobj' IN SECTION OFFSET lv_obj_pos OF mv_pdf_text MATCH OFFSET lv_endobj_pos.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.
      lv_endobj_pos = lv_endobj_pos + lv_obj_pos.

      DATA lv_raw_obj_len TYPE i.
      DATA lv_raw_obj TYPE string.
      lv_raw_obj_len = lv_endobj_pos - lv_obj_pos.
      lv_raw_obj = mv_pdf_text+lv_obj_pos(lv_raw_obj_len).
      APPEND NEW zcl_pdf_object( iv_id = lv_id_s iv_generation = lv_gen_s iv_raw = lv_raw_obj ) TO mt_objects.

      lv_pos = lv_endobj_pos + 6.
    ENDWHILE.
  ENDMETHOD.

  METHOD get_object.
    LOOP AT mt_objects INTO DATA(lo_object).
      IF lo_object->get_id( ) = iv_obj_id.
        ro_object = lo_object.
        RETURN.
      ENDIF.
    ENDLOOP.

    RAISE EXCEPTION TYPE zcx_pdf_error
      EXPORTING iv_message = |Object { iv_obj_id } not loaded.|.
  ENDMETHOD.

  METHOD get_trailer_value.
    READ TABLE mt_trailer WITH KEY key = iv_key INTO DATA(ls_item).
    IF sy-subrc = 0.
      rv_value = ls_item-value.
    ENDIF.
  ENDMETHOD.


  METHOD get_objects.
    rt_objects = mt_objects.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_pdf_parser DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS should_find_trailer FOR TESTING.
ENDCLASS.

CLASS ltcl_pdf_parser IMPLEMENTATION.
  METHOD should_find_trailer.
    DATA(lv_pdf) = |%PDF-1.4{ cl_abap_char_utilities=>newline }1 0 obj{ cl_abap_char_utilities=>newline }<< /Type /Catalog >>{ cl_abap_char_utilities=>newline }endobj{ cl_abap_char_utilities=>newline }xref{ cl_abap_char_utilities=>newline }0 2{ cl_abap_char_utilities=>newline }0000000000 65535 f { cl_abap_char_utilities=>newline }0000000009 00000 n { cl_abap_char_utilities=>newline }trailer{ cl_abap_char_utilities=>newline }<< /Root 1 0 R /Size 2 >>{ cl_abap_char_utilities=>newline }startxref{ cl_abap_char_utilities=>newline }63{ cl_abap_char_utilities=>newline }%%EOF|.
    DATA(lo_parser) = NEW zcl_pdf_parser( ).

    lo_parser->parse( zcl_pdf_utils=>string_to_xstring( lv_pdf ) ).

    cl_abap_unit_assert=>assert_not_initial( lo_parser->get_trailer_value( '/Root' ) ).
  ENDMETHOD.
ENDCLASS.
