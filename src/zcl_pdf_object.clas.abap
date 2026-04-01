CLASS zcl_pdf_object DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_dict_item,
             key   TYPE string,
             value TYPE string,
           END OF ty_dict_item,
           tt_dict_item TYPE HASHED TABLE OF ty_dict_item WITH UNIQUE KEY key,
           tt_string TYPE STANDARD TABLE OF string WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING
        iv_id         TYPE i
        iv_generation TYPE i
        iv_raw        TYPE string
        iv_raw_binary TYPE xstring OPTIONAL.

    METHODS get_id RETURNING VALUE(rv_id) TYPE i.
    METHODS get_generation RETURNING VALUE(rv_generation) TYPE i.
    METHODS get_raw_content RETURNING VALUE(rv_raw) TYPE string.
    METHODS get_dictionary RETURNING VALUE(rt_dict) TYPE tt_dict_item.
    METHODS get_stream RETURNING VALUE(rv_stream) TYPE xstring.
    METHODS get_filters RETURNING VALUE(rt_filters) TYPE tt_string.
    METHODS has_stream RETURNING VALUE(rv_has_stream) TYPE abap_bool.

  PRIVATE SECTION.
    DATA mv_id TYPE i.
    DATA mv_generation TYPE i.
    DATA mv_raw TYPE string.
    DATA mv_raw_binary TYPE xstring.
    DATA mt_dict TYPE tt_dict_item.
    DATA mv_stream_raw TYPE xstring.
    DATA mt_filters TYPE tt_string.

    METHODS parse_dictionary.
    METHODS parse_stream.
ENDCLASS.

CLASS zcl_pdf_object IMPLEMENTATION.
  METHOD constructor.
    mv_id = iv_id.
    mv_generation = iv_generation.
    mv_raw = iv_raw.
    mv_raw_binary = iv_raw_binary.
    parse_dictionary( ).
    parse_stream( ).
  ENDMETHOD.

  METHOD parse_dictionary.
    DATA lv_begin TYPE i.
    DATA lv_end TYPE i.
    DATA lv_dict_text TYPE string.

    FIND FIRST OCCURRENCE OF '<<' IN mv_raw MATCH OFFSET lv_begin.
    FIND FIRST OCCURRENCE OF '>>' IN mv_raw MATCH OFFSET lv_end.
    IF sy-subrc <> 0 OR lv_end <= lv_begin.
      RETURN.
    ENDIF.

    DATA lv_dict_off TYPE i.
    DATA lv_dict_len TYPE i.
    lv_dict_off = lv_begin + 2.
    lv_dict_len = lv_end - lv_begin - 2.
    lv_dict_text = mv_raw+lv_dict_off(lv_dict_len).
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN lv_dict_text WITH space.
    CONDENSE lv_dict_text.

    DATA lt_tokens TYPE tt_string.
    SPLIT lv_dict_text AT space INTO TABLE lt_tokens.

    DATA lv_key TYPE string.
    LOOP AT lt_tokens INTO DATA(lv_token).
      IF lv_token CP '/*'.
        lv_key = lv_token.
      ELSEIF lv_key IS NOT INITIAL.
        IF lv_key = '/Filter'.
          DATA(lv_filter_value) = lv_token.
          IF lv_filter_value = '['.
            CLEAR lv_filter_value.
            DATA(lv_filter_index) = sy-tabix + 1.
            LOOP AT lt_tokens INTO DATA(lv_filter_token) FROM lv_filter_index.
              IF lv_filter_token = ']'.
                EXIT.
              ENDIF.
              IF lv_filter_token CP '/*'.
                IF lv_filter_value IS INITIAL.
                  lv_filter_value = lv_filter_token.
                ELSE.
                  lv_filter_value = |{ lv_filter_value } { lv_filter_token }|.
                ENDIF.
                APPEND lv_filter_token TO mt_filters.
              ENDIF.
            ENDLOOP.
          ELSEIF lv_filter_value CP '/*'.
            APPEND lv_filter_value TO mt_filters.
          ENDIF.
          INSERT VALUE ty_dict_item( key = lv_key value = lv_filter_value ) INTO TABLE mt_dict.
        ELSE.
          INSERT VALUE ty_dict_item( key = lv_key value = lv_token ) INTO TABLE mt_dict.
        ENDIF.
        CLEAR lv_key.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD parse_stream.
    DATA lv_stream_pos TYPE i.
    DATA lv_endstream_pos TYPE i.
    FIND FIRST OCCURRENCE OF 'stream' IN mv_raw MATCH OFFSET lv_stream_pos.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    FIND FIRST OCCURRENCE OF 'endstream' IN mv_raw MATCH OFFSET lv_endstream_pos.
    IF sy-subrc <> 0 OR lv_endstream_pos <= lv_stream_pos.
      RETURN.
    ENDIF.

    DATA lv_stream_off TYPE i.
    DATA lv_stream_len TYPE i.
    DATA lv_stream_txt TYPE string.
    lv_stream_off = lv_stream_pos + 6.
    lv_stream_len = lv_endstream_pos - lv_stream_pos - 6.
    IF mv_raw_binary IS INITIAL.
      lv_stream_txt = mv_raw+lv_stream_off(lv_stream_len).
      SHIFT lv_stream_txt LEFT DELETING LEADING cl_abap_char_utilities=>newline.
      mv_stream_raw = zcl_pdf_utils=>string_to_xstring( lv_stream_txt ).
      RETURN.
    ENDIF.

    mv_stream_raw = mv_raw_binary+lv_stream_off(lv_stream_len).
    IF xstrlen( mv_stream_raw ) > 0 AND mv_stream_raw(1) = '0A'.
      mv_stream_raw = mv_stream_raw+1.
    ELSEIF xstrlen( mv_stream_raw ) > 1 AND mv_stream_raw(2) = '0D0A'.
      mv_stream_raw = mv_stream_raw+2.
    ENDIF.
  ENDMETHOD.

  METHOD get_id.
    rv_id = mv_id.
  ENDMETHOD.

  METHOD get_generation.
    rv_generation = mv_generation.
  ENDMETHOD.

  METHOD get_raw_content.
    rv_raw = mv_raw.
  ENDMETHOD.

  METHOD get_dictionary.
    rt_dict = mt_dict.
  ENDMETHOD.

  METHOD get_stream.
    rv_stream = mv_stream_raw.
  ENDMETHOD.

  METHOD get_filters.
    rt_filters = mt_filters.
  ENDMETHOD.

  METHOD has_stream.
    rv_has_stream = xsdbool( mv_stream_raw IS NOT INITIAL ).
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_pdf_object DEFINITION FINAL FOR TESTING DURATION SHORT RISK LEVEL HARMLESS.
  PRIVATE SECTION.
    METHODS should_parse_filter_array FOR TESTING.
    METHODS should_keep_binary_stream_bytes FOR TESTING.
ENDCLASS.

CLASS ltcl_pdf_object IMPLEMENTATION.
  METHOD should_parse_filter_array.
    DATA(lv_raw) = |1 0 obj{ cl_abap_char_utilities=>newline }<< /Length 5 /Filter [ /FlateDecode /ASCII85Decode ] >>{ cl_abap_char_utilities=>newline }stream{ cl_abap_char_utilities=>newline }abcde{ cl_abap_char_utilities=>newline }endstream{ cl_abap_char_utilities=>newline }endobj|.
    DATA(lo_object) = NEW zcl_pdf_object( iv_id = 1 iv_generation = 0 iv_raw = lv_raw ).
    DATA(lt_filters) = lo_object->get_filters( ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_filters ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lt_filters[ 1 ] exp = '/FlateDecode' ).
    cl_abap_unit_assert=>assert_equals( act = lt_filters[ 2 ] exp = '/ASCII85Decode' ).
  ENDMETHOD.

  METHOD should_keep_binary_stream_bytes.
    DATA(lv_prefix) = |1 0 obj{ cl_abap_char_utilities=>newline }<< /Length 3 /Filter /FlateDecode >>{ cl_abap_char_utilities=>newline }stream{ cl_abap_char_utilities=>newline }|.
    DATA(lv_suffix) = |{ cl_abap_char_utilities=>newline }endstream{ cl_abap_char_utilities=>newline }endobj|.
    DATA(lv_stream_expected) TYPE xstring VALUE 'FF00A1'.
    DATA(lv_raw_binary) = zcl_pdf_utils=>string_to_xstring( lv_prefix ) && lv_stream_expected && zcl_pdf_utils=>string_to_xstring( lv_suffix ).
    DATA(lv_raw_text) = zcl_pdf_utils=>xstring_to_latin1_string( lv_raw_binary ).
    DATA(lo_object) = NEW zcl_pdf_object( iv_id = 1 iv_generation = 0 iv_raw = lv_raw_text iv_raw_binary = lv_raw_binary ).

    cl_abap_unit_assert=>assert_equals( act = lo_object->get_stream( ) exp = lv_stream_expected ).
  ENDMETHOD.
ENDCLASS.
