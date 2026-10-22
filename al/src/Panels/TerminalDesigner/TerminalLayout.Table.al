table 72382 "DOPSWHS Terminal Layout"
{
    // Terminal Ekran Tasarımcısı: el terminali ana menüsü ve ekran düğmeleri için
    // şirket bazlı, isteğe bağlı rol/terminal hedefli yerleşim. Yalnız gizler,
    // sıralar ve yeniden adlandırır; terminalin kendi yetki kuralları her zaman
    // önce uygulanır (yerleşim erişim VERMEZ).
    Caption = 'Terminal Layout';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Code"; Code[20])
        {
            Caption = 'Kod';
            NotBlank = true;
        }
        field(2; Description; Text[100])
        {
            Caption = 'Açıklama';
        }
        field(3; "Applies-to Type"; Option)
        {
            Caption = 'Uygulandığı';
            OptionMembers = All,Role,Terminal;
            OptionCaption = 'Tüm terminaller,Rol,Terminal';

            trigger OnValidate()
            begin
                if "Applies-to Type" = "Applies-to Type"::All then
                    "Applies-to Code" := '';
            end;
        }
        field(4; "Applies-to Code"; Code[20])
        {
            Caption = 'Rol / Terminal Kodu';
            TableRelation = if ("Applies-to Type" = const(Role)) "DOPSWHS App Role".Code
            else
            if ("Applies-to Type" = const(Terminal)) "DOPSWHS WMS Terminal".Code;
        }
        field(5; Active; Boolean)
        {
            Caption = 'Etkin';
            InitValue = true;
        }
        field(6; "Version No."; Integer)
        {
            Caption = 'Sürüm';
            Editable = false;
        }
        field(7; "Last Modified At"; DateTime)
        {
            Caption = 'Son Değişiklik';
            Editable = false;
        }
        field(8; "Last Modified By"; Code[50])
        {
            Caption = 'Değiştiren';
            Editable = false;
            DataClassification = EndUserIdentifiableInformation;
        }
        // 50-52: yalnız terminalLayouts API'sinin GEÇİCİ tamponunda kullanılır
        // ($filter=terminalCode eq 'T1' and userName eq 'AHMET'). Kalıcı kayıtta boş kalır.
        field(50; "Request Terminal Code"; Code[20])
        {
            Caption = 'İstek Terminal Kodu';
            Editable = false;
        }
        field(51; "Request Role Code"; Code[20])
        {
            Caption = 'İstek Rol Kodu';
            Editable = false;
        }
        field(52; "Request User Name"; Code[20])
        {
            Caption = 'İstek Kullanıcı Adı';
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Code") { Clustered = true; }
        key(Target; "Applies-to Type", "Applies-to Code", Active) { }
    }

    trigger OnDelete()
    var
        Line: Record "DOPSWHS Terminal Layout Line";
    begin
        Line.SetRange("Layout Code", Code);
        Line.DeleteAll();
    end;

    trigger OnModify()
    begin
        "Last Modified At" := CurrentDateTime();
        "Last Modified By" := CopyStr(UserId(), 1, MaxStrLen("Last Modified By"));
    end;

    trigger OnInsert()
    begin
        "Last Modified At" := CurrentDateTime();
        "Last Modified By" := CopyStr(UserId(), 1, MaxStrLen("Last Modified By"));
    end;
}
