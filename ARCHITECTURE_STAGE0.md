# ABAP PDF Text Extractor — Stage 0 Architecture

## Scope and goals

This stage defines a production-oriented architecture for an ABAP 7.4 / SAP NetWeaver library that extracts text from PDF files with a structured parser (not regex-only parsing).

Processing pipeline:

1. Reader (input loading)
2. Structural parser (startxref/xref/trailer/object parsing)
3. Object model + reference resolver
4. Stream decoder (FlateDecode mandatory, extensible filters)
5. Content stream interpreter (text operators)
6. Font/encoding decoder (WinAnsi + minimal ToUnicode CMap)
7. Orchestration API (`extract_text`)

---

## Layered architecture

### 1) Reader layer

**Class:** `ZCL_PDF_READER`  
**Responsibility:** input and orchestration entrypoint.

- Load PDF from frontend (`GUI_UPLOAD`-based xstring pipeline).
- Load PDF from application server (`OPEN DATASET ... IN BINARY MODE`).
- Keep raw PDF as `xstring`.
- Expose high-level extraction method that orchestrates parser/decoder/extractor.

Public API (target):

- `LOAD_FROM_FRONTEND( iv_filename )`
- `LOAD_FROM_APP_SERVER( iv_path )`
- `GET_RAW_DATA( ) RETURNING rv_pdf_raw TYPE xstring`
- `EXTRACT_TEXT( ) RETURNING rv_text TYPE string`

---

### 2) Parser layer

**Classes:** `ZCL_PDF_PARSER`, `ZCL_PDF_XREF`  
**Responsibility:** parse PDF file structure from raw bytes.

#### `ZCL_PDF_PARSER`

- Validate PDF header (`%PDF-`).
- Find `startxref` from end of file.
- Delegate xref parsing to `ZCL_PDF_XREF`.
- Parse trailer dictionary (`/Root`, `/Size`, `/Info`).
- Parse objects by offsets (`obj ... endobj`).
- Parse object bodies into structured model.
- Resolve indirect references lazily/eagerly (configurable later).

Public API (target):

- `PARSE( iv_pdf_raw TYPE xstring )`
- `PARSE_ALL_OBJECTS( )`
- `GET_OBJECT( iv_obj_id TYPE i iv_gen TYPE i ) RETURNING ro_object TYPE REF TO zcl_pdf_object`
- `GET_ROOT_REFERENCE( )`

#### `ZCL_PDF_XREF`

- Parse classic xref tables (phase 1).
- Store object offsets + generations + free/in-use flags.
- Provide offset lookup by object id.
- Keep design extensible for xref streams (future phase).

Public API (target):

- `READ_XREF_TABLE( iv_pdf_raw TYPE xstring iv_startxref TYPE i )`
- `GET_OBJECT_OFFSET( iv_obj_id TYPE i ) RETURNING rv_offset TYPE i`
- `HAS_OBJECT( iv_obj_id TYPE i ) RETURNING rv_exists TYPE abap_bool`

---

### 3) Object model layer

**Classes:** `ZCL_PDF_OBJECT`, `ZCL_PDF_STREAM`  
**Responsibility:** represent parsed PDF entities.

#### `ZCL_PDF_OBJECT`

Fields (target):

- `mv_id TYPE i`
- `mv_generation TYPE i`
- `mv_raw_content TYPE xstring`
- `mo_dictionary TYPE REF TO zcl_pdf_dictionary` (or internal structured type)
- `mo_stream TYPE REF TO zcl_pdf_stream`
- `mv_type TYPE string` (catalog/page/font/etc. derived)

Behavior:

- Parse dictionary section (`<< >>`) into key-value map.
- Expose typed getters for key lookup and refs.

#### `ZCL_PDF_STREAM`

Fields:

- `mv_raw_stream TYPE xstring`
- `mv_decoded_stream TYPE xstring`
- `mt_filters TYPE STANDARD TABLE OF string`

Behavior:

- Keep stream bytes split from dictionary metadata.
- Decode via `ZCL_PDF_STREAM_DECODER`.

---

### 4) Stream decoding layer

**Class:** `ZCL_PDF_STREAM_DECODER`  
**Responsibility:** decode stream data using declared filters.

Phase-1 mandatory filter:

- `FlateDecode`.

Design constraints:

- Binary-safe processing (`xstring` only in decode stage).
- Filter-chain support for multiple filters (`/Filter` name or array).
- Explicit error on unsupported filters.

Public API (target):

- `DECODE( iv_stream TYPE xstring it_filters TYPE STANDARD TABLE OF string ) RETURNING rv_decoded TYPE xstring`

Implementation note:

- Use standard ABAP compression/decompression facilities available in NetWeaver stack for zlib/deflate handling.

---

### 5) Text extraction layer

**Class:** `ZCL_PDF_TEXT_EXTRACTOR`  
**Responsibility:** parse content streams and extract textual payload.

Phase-1 operator support:

- `BT` / `ET` text objects
- `Tf` font selection
- `Td` / `TD` positioning (tracked minimally)
- `Tj` single string show
- `TJ` array show
- (`'` and `"` can be added in same parser framework)

Behavior:

- Tokenize content stream operators/operands.
- Maintain minimal text state (inside-text flag, current font resource).
- Collect text in reading order approximation from stream sequence.

Public API (target):

- `EXTRACT_TEXT( iv_content_stream TYPE xstring io_font_decoder TYPE REF TO zcl_pdf_font_decoder ) RETURNING rv_text TYPE string`

---

### 6) Font/encoding layer

**Class:** `ZCL_PDF_FONT_DECODER`  
**Responsibility:** convert PDF string bytes to Unicode string.

Phase-1 support:

- Literal and hexadecimal PDF strings.
- WinAnsiEncoding baseline.
- Minimal ToUnicode CMap parsing for `bfchar`/`bfrange` mappings.

Public API (target):

- `DECODE_TEXT_OPERAND( iv_pdf_string TYPE xstring iv_font_name TYPE string is_font_context TYPE zpdf_font_context ) RETURNING rv_text TYPE string`
- `REGISTER_FONT( ... )`

---

## Interfaces and loose coupling

To keep low coupling and enable extensions:

- `ZIF_PDF_STREAM_DECODER` for stream decode strategy.
- `ZIF_PDF_TEXT_EXTRACTOR` for content interpretation strategy.
- `ZIF_PDF_FONT_DECODER` for encoding strategy.
- `ZIF_PDF_SOURCE` (optional) for unified source abstraction.

`ZCL_PDF_READER` depends on interfaces where feasible, concrete defaults supplied in constructor.

---

## Error handling model

Use domain-specific exceptions:

- `ZCX_PDF_ERROR` (base)
- `ZCX_PDF_PARSE_ERROR`
- `ZCX_PDF_UNSUPPORTED_FEATURE`
- `ZCX_PDF_DECODE_ERROR`

Principles:

- Fail-fast on invalid structure (missing `startxref`, malformed object boundaries).
- Explicit unsupported-feature errors (rather than silent skip) for production observability.

---

## TDD plan for next stages

### Unit test classes (ABAP Unit)

1. `ltcl_pdf_parser`
   - finds `startxref`
   - reads trailer keys
   - parses object boundaries
2. `ltcl_pdf_xref`
   - resolves object offsets from synthetic xref
3. `ltcl_stream_decoder`
   - FlateDecode known compressed payload
4. `ltcl_text_extractor`
   - `Tj`/`TJ` extraction from synthetic content stream
5. `ltcl_font_decoder`
   - WinAnsi mapping
   - minimal ToUnicode mapping

### Iterative delivery order

1. Reader raw loading
2. `startxref` + xref + trailer
3. Object parsing/model
4. FlateDecode
5. Text operators (`Tj`, `TJ`, `BT`, `ET`, `Tf`, `Td`)
6. Font decoding baseline + ToUnicode minimal
7. Orchestration + integrated tests

---

## Non-goals for first increment

- Full graphical/layout reconstruction.
- OCR or image-based text extraction.
- Complete PDF spec coverage (focus on robust text extraction path).

