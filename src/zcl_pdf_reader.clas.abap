CLASS zcl_pdf_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Loads a PDF file from the SAP GUI frontend into raw binary form.
    METHODS load_from_frontend
      IMPORTING
        iv_filename TYPE string OPTIONAL
      RAISING
        zcx_pdf_error.

    " Loads a PDF file from the application server into raw binary form.
    METHODS load_from_app_server
      IMPORTING
        iv_path TYPE string
      RAISING
        zcx_pdf_error.

    " Returns the currently loaded raw PDF payload.
    METHODS get_raw_data
      RETURNING
        VALUE(rv_pdf_raw) TYPE xstring.

    " Helper for tests and integration scenarios that already provide xstring payload.
    METHODS load_from_xstring
      IMPORTING
        iv_pdf_raw TYPE xstring.

    " Full text extraction pipeline (load -> parse -> decode stream -> extract text).
    METHODS extract_text
      RETURNING
        VALUE(rv_text) TYPE string
      RAISING
        zcx_pdf_error.

  PRIVATE SECTION.
    DATA mv_pdf_raw TYPE xstring.
ENDCLASS.


CLASS zcl_pdf_reader IMPLEMENTATION.
  METHOD load_from_frontend.
    DATA lt_binary     TYPE solix_tab.
    DATA lv_filelength TYPE i.
    DATA lv_filename   TYPE string.

    CLEAR mv_pdf_raw.

    lv_filename = iv_filename.
    IF lv_filename IS INITIAL.
      DATA lt_filetable TYPE filetable.
      DATA lv_rc TYPE i.

      cl_gui_frontend_services=>file_open_dialog(
        EXPORTING
          multiselection = abap_false
          file_filter    = 'PDF (*.pdf)|*.pdf|'
        CHANGING
          file_table     = lt_filetable
          rc             = lv_rc
        EXCEPTIONS
          file_open_dialog_failed = 1
          cntl_error              = 2
          error_no_gui            = 3
          not_supported_by_gui    = 4
          OTHERS                  = 5 ).

      IF sy-subrc <> 0 OR lv_rc <= 0.
        RAISE EXCEPTION TYPE zcx_pdf_error
          EXPORTING
            iv_message = |File selection dialog was canceled or failed (subrc={ sy-subrc }).|.
      ENDIF.

      READ TABLE lt_filetable INDEX 1 INTO DATA(ls_file).
      IF sy-subrc <> 0 OR ls_file-filename IS INITIAL.
        RAISE EXCEPTION TYPE zcx_pdf_error
          EXPORTING
            iv_message = 'No file selected in frontend dialog.'.
      ENDIF.

      lv_filename = ls_file-filename.
    ENDIF.

    cl_gui_frontend_services=>gui_upload(
      EXPORTING
        filename                = lv_filename
        filetype                = 'BIN'
      IMPORTING
        filelength              = lv_filelength
      CHANGING
        data_tab                = lt_binary
      EXCEPTIONS
        file_open_error         = 1
        file_read_error         = 2
        no_batch                = 3
        gui_refuse_filetransfer = 4
        invalid_type            = 5
        no_authority            = 6
        unknown_error           = 7
        bad_data_format         = 8
        header_not_allowed      = 9
        separator_not_allowed   = 10
        header_too_long         = 11
        unknown_dp_error        = 12
        access_denied           = 13
        dp_out_of_memory        = 14
        disk_full               = 15
        dp_timeout              = 16
        not_supported_by_gui    = 17
        error_no_gui            = 18
        OTHERS                  = 19 ).

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING
          iv_message = |Failed to load frontend file "{ lv_filename }" (subrc={ sy-subrc }).|.
    ENDIF.

    CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
      EXPORTING
        input_length = lv_filelength
      IMPORTING
        buffer       = mv_pdf_raw
      TABLES
        binary_tab   = lt_binary
      EXCEPTIONS
        failed       = 1
        OTHERS       = 2.

    IF sy-subrc <> 0.
      CLEAR mv_pdf_raw.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING
          iv_message = |Failed to convert frontend payload to xstring (subrc={ sy-subrc }).|.
    ENDIF.
  ENDMETHOD.

  METHOD load_from_app_server.
    DATA lv_buffer TYPE x LENGTH 8192.
    DATA lv_length TYPE i.
    DATA lv_raw    TYPE xstring.

    CLEAR mv_pdf_raw.

    OPEN DATASET iv_path FOR INPUT IN BINARY MODE.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING
          iv_message = |Failed to open application server file "{ iv_path }" (subrc={ sy-subrc }).|.
    ENDIF.

    DO.
      READ DATASET iv_path INTO lv_buffer LENGTH lv_length.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      IF lv_length > 0.
        lv_raw = lv_raw && lv_buffer(lv_length).
      ENDIF.
    ENDDO.

    CLOSE DATASET iv_path.
    mv_pdf_raw = lv_raw.
  ENDMETHOD.

  METHOD get_raw_data.
    rv_pdf_raw = mv_pdf_raw.
  ENDMETHOD.

  METHOD load_from_xstring.
    mv_pdf_raw = iv_pdf_raw.
  ENDMETHOD.

  METHOD extract_text.
    DATA(lo_parser) = NEW zcl_pdf_parser( ).
    DATA(lo_stream_decoder) = NEW zcl_pdf_stream_decoder( ).
    DATA(lo_text_extractor) = NEW zcl_pdf_text_extractor( ).
    DATA(lo_font_decoder) = NEW zcl_pdf_font_decoder( ).

    IF mv_pdf_raw IS INITIAL.
      RAISE EXCEPTION TYPE zcx_pdf_error
        EXPORTING iv_message = 'No PDF data loaded'.
    ENDIF.

    lo_parser->parse( mv_pdf_raw ).

    DATA(lt_objects) = lo_parser->get_objects( ).

    LOOP AT lt_objects INTO DATA(lo_obj).
      IF lo_obj->has_stream( ) = abap_false.
        CONTINUE.
      ENDIF.

      DATA(lv_decoded) = lo_stream_decoder->decode(
        iv_stream = lo_obj->get_stream( )
        it_filters = lo_obj->get_filters( ) ).

      rv_text = rv_text && lo_text_extractor->extract_text(
        iv_content_stream = lv_decoded
        io_font_decoder   = lo_font_decoder ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.


CLASS ltcl_pdf_reader DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS should_return_loaded_raw_data FOR TESTING.
    METHODS should_be_empty_initially FOR TESTING.
ENDCLASS.


CLASS ltcl_pdf_reader IMPLEMENTATION.
  METHOD should_return_loaded_raw_data.
    DATA(lo_reader) = NEW zcl_pdf_reader( ).
    DATA(lv_raw) = '255044462D312E340A' ##NO_TEXT.

    lo_reader->load_from_xstring( lv_raw ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_reader->get_raw_data( )
      exp = lv_raw ).
  ENDMETHOD.

  METHOD should_be_empty_initially.
    DATA(lo_reader) = NEW zcl_pdf_reader( ).

    cl_abap_unit_assert=>assert_initial( lo_reader->get_raw_data( ) ).
  ENDMETHOD.
ENDCLASS.
