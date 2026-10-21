// Kitoko (21 Eki 2026): etiket tasarımcısına yüklenen resimler ve şirket logosunun
// kopyası (COMPANY). Resmin kendisi data URL olarak saklanır; basılan ^GFA verisi
// tasarım satırındadır (tasarımcı eleman boyutu + dpi ile üretir).
table 72472 "DOPSWHS Label Image"
{
    Caption = 'Etiket Resmi';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS Label Image List";
    DrillDownPageId = "DOPSWHS Label Image List";

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Kod';
            DataClassification = CustomerContent;
            NotBlank = true;
        }
        field(2; Name; Text[100])
        {
            Caption = 'Ad';
            DataClassification = CustomerContent;
        }
        field(3; Image; Blob)
        {
            Caption = 'Resim';
            DataClassification = CustomerContent;
        }
        field(4; "Width (px)"; Integer)
        {
            Caption = 'Genişlik (px)';
            DataClassification = CustomerContent;
            MinValue = 0;
        }
        field(5; "Height (px)"; Integer)
        {
            Caption = 'Yükseklik (px)';
            DataClassification = CustomerContent;
            MinValue = 0;
        }
        field(6; "Last Modified"; DateTime)
        {
            Caption = 'Son Değişiklik';
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Code") { Clustered = true; }
    }

    trigger OnInsert()
    begin
        "Last Modified" := CurrentDateTime();
    end;

    trigger OnModify()
    begin
        "Last Modified" := CurrentDateTime();
    end;

    /// <summary>The stored image as a data URL (data:image/...;base64,...); '' when empty.</summary>
    procedure GetDataUrl(): Text
    var
        TypeHelper: Codeunit "Type Helper";
        InStr: InStream;
        LF: Char;
    begin
        CalcFields(Image);
        if not Image.HasValue() then
            exit('');
        Image.CreateInStream(InStr, TextEncoding::UTF8);
        LF := 10;
        exit(TypeHelper.ReadAsTextWithSeparator(InStr, Format(LF)));
    end;

    procedure SetDataUrl(Value: Text)
    var
        OutStr: OutStream;
    begin
        Clear(Image);
        if Value = '' then
            exit;
        Image.CreateOutStream(OutStr, TextEncoding::UTF8);
        OutStr.WriteText(Value);
    end;
}
