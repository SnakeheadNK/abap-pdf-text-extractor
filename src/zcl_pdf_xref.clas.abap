CLASS zcl_pdf_xref DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_entry,
             obj_id     TYPE i,
             offset     TYPE i,
             generation TYPE i,
             in_use     TYPE abap_bool,
           END OF ty_entry,
           tt_entry TYPE HASHED TABLE OF ty_entry WITH UNIQUE KEY obj_id.

    METHODS read_xref_table
      IMPORTING
        iv_pdf_text   TYPE string
        iv_startxref  TYPE i
      RAISING
        zcx_pdf_error.

    METHODS get_object_offset
      IMPORTING
        iv_obj_id TYPE i
      RETURNING
        VALUE(rv_offset) TYPE i
      RAISING
        zcx_pdf_error.

    METHODS has_object
      IMPORTING
        iv_obj_id TYPE i
      RETURNING
        VALUE(rv_exists) TYPE abap_bool.

  PRIVATE SECTION.
    DATA mt_entries TYPE tt_entry.
ENDCLASS.

CLASS zcl_pdf_xref IMPLEMENTATION.
  METHOD read_xref_table.
    DATA lt_lines TYPE tt_string.
    DATA lv_line TYPE string.
    DATA lv_index TYPE i.
    DATA lv_subsection_start TYPE i.
    DATA lv_subsection_count TYPE i.
    DATA lv_obj TYPE i.

    CLEAR mt_entries.

    SPLIT substring( val = iv_pdf_text off = iv_startxref ) AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    DELETE lt_lines WHERE table_line IS INITIAL.

    READ TABLE lt_lines INDEX 1 INTO lv_line.
    IF sy-subrc <> 0 OR lv_line NS 'xref'.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = 'Invalid xref section'.
    ENDIF.

    lv_index = 2.
    WHILE lv_index <= lines( lt_lines ).
      READ TABLE lt_lines INDEX lv_index INTO lv_line.
      IF sy-subrc <> 0 OR lv_line CS 'trailer'.
        EXIT.
      ENDIF.

      DATA lv_start_s TYPE string.
      DATA lv_count_s TYPE string.
      FIND FIRST OCCURRENCE OF REGEX '^([0-9]+)[[:space:]]+([0-9]+)$' IN lv_line SUBMATCHES lv_start_s lv_count_s.
      IF sy-subrc <> 0.
        lv_index = lv_index + 1.
        CONTINUE.
      ENDIF.

      lv_subsection_start = lv_start_s.
      lv_subsection_count = lv_count_s.
      lv_index = lv_index + 1.

      DO lv_subsection_count TIMES.
        READ TABLE lt_lines INDEX lv_index INTO lv_line.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.

        DATA lv_offset_s TYPE string.
        DATA lv_gen_s TYPE string.
        DATA lv_flag TYPE string.
        FIND FIRST OCCURRENCE OF REGEX '^([0-9]{10})[[:space:]]+([0-9]{5})[[:space:]]+([nf])' IN lv_line SUBMATCHES lv_offset_s lv_gen_s lv_flag.
        IF sy-subrc <> 0.
          lv_index = lv_index + 1.
          CONTINUE.
        ENDIF.

        lv_obj = lv_subsection_start + sy-index - 1.
        INSERT VALUE ty_entry(
          obj_id = lv_obj
          offset = lv_offset_s
          generation = lv_gen_s
          in_use = xsdbool( lv_flag = 'n' ) ) INTO TABLE mt_entries.

        lv_index = lv_index + 1.
      ENDDO.
    ENDWHILE.
  ENDMETHOD.

  METHOD get_object_offset.
    READ TABLE mt_entries WITH KEY obj_id = iv_obj_id INTO DATA(ls_entry).
    IF sy-subrc <> 0 OR ls_entry-in_use = abap_false.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = |Object { iv_obj_id } not found in xref.|.
    ENDIF.
    rv_offset = ls_entry-offset.
  ENDMETHOD.

  METHOD has_object.
    READ TABLE mt_entries WITH KEY obj_id = iv_obj_id TRANSPORTING NO FIELDS.
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_pdf_xref DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS should_read_offsets FOR TESTING.
ENDCLASS.

CLASS ltcl_pdf_xref IMPLEMENTATION.
  METHOD should_read_offsets.
    DATA(lv_pdf) = |xref{ cl_abap_char_utilities=>newline }0 2{ cl_abap_char_utilities=>newline }0000000000 65535 f { cl_abap_char_utilities=>newline }0000000017 00000 n { cl_abap_char_utilities=>newline }trailer|.
    DATA(lo_xref) = NEW zcl_pdf_xref( ).

    lo_xref->read_xref_table( iv_pdf_text = lv_pdf iv_startxref = 0 ).

    cl_abap_unit_assert=>assert_equals( act = lo_xref->get_object_offset( 1 ) exp = 17 ).
  ENDMETHOD.
ENDCLASS.
