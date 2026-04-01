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
      IF lv_key IS NOT INITIAL.
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
      ELSEIF lv_token CP '/*'.
        lv_key = lv_token.
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
    FIND FIRST OCCURRENCE OF 'endstream' IN SECTION OFFSET lv_stream_pos OF mv_raw MATCH OFFSET lv_endstream_pos.
    IF sy-subrc <> 0 OR lv_endstream_pos <= lv_stream_pos.
      RETURN.
    ENDIF.

    lv_endstream_pos = lv_endstream_pos + lv_stream_pos.

    DATA lv_data_start TYPE i.
    lv_data_start = lv_stream_pos + 6.

    IF mv_raw+lv_data_start(2) = cl_abap_char_utilities=>cr_lf.
      lv_data_start = lv_data_start + 2.
    ELSEIF mv_raw+lv_data_start(1) = cl_abap_char_utilities=>newline.
      lv_data_start = lv_data_start + 1.
    ENDIF.

    DATA(lv_stream_len) = lv_endstream_pos - lv_data_start.
    IF lv_stream_len <= 0.
      RETURN.
    ENDIF.

    IF mv_raw_binary IS NOT INITIAL.
      mv_stream_raw = mv_raw_binary+lv_data_start(lv_stream_len).
    ELSE.
      DATA(lv_stream_txt) = mv_raw+lv_data_start(lv_stream_len).
      DATA(lo_conv) = cl_abap_conv_out_ce=>create( encoding = 'ISO-8859-1' ).
      lo_conv->write( data = lv_stream_txt ).
      mv_stream_raw = lo_conv->get_buffer( ).
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
    METHODS should_keep_name_value_for_filter FOR TESTING.
    METHODS should_extract_stream_payload_without_eol FOR TESTING.
ENDCLASS.

CLASS ltcl_pdf_object IMPLEMENTATION.
  METHOD should_keep_name_value_for_filter.
    DATA(lo_object) = NEW zcl_pdf_object(
      iv_id = 1
      iv_generation = 0
      iv_raw = '1 0 obj << /Filter /FlateDecode /Length 5 >> endobj' ).

    DATA(lt_dict) = lo_object->get_dictionary( ).
    READ TABLE lt_dict WITH KEY key = '/Filter' INTO DATA(ls_filter).

    cl_abap_unit_assert=>assert_equals( act = ls_filter-value exp = '/FlateDecode' ).
    cl_abap_unit_assert=>assert_equals( act = lines( lo_object->get_filters( ) ) exp = 1 ).
  ENDMETHOD.

  METHOD should_extract_stream_payload_without_eol.
    DATA(lv_raw) = |1 0 obj{ cl_abap_char_utilities=>newline }<< /Length 5 >>{ cl_abap_char_utilities=>newline }stream{ cl_abap_char_utilities=>newline }Hello{ cl_abap_char_utilities=>newline }endstream{ cl_abap_char_utilities=>newline }endobj|.
    DATA(lo_object) = NEW zcl_pdf_object(
      iv_id = 1
      iv_generation = 0
      iv_raw = lv_raw
      iv_raw_binary = zcl_pdf_utils=>string_to_xstring( lv_raw ) ).

    DATA(lv_stream) = lo_object->get_stream( ).

    cl_abap_unit_assert=>assert_equals(
      act = zcl_pdf_utils=>xstring_to_latin1_string( lv_stream )
      exp = 'Hello' ).
  ENDMETHOD.
ENDCLASS.
