/// <summary>Asks which document the LP card should pull its lines from.</summary>
page 72318 "DOPSWHS LP Pull Document"
{
    Caption = 'Belgeden Satırları Çek';
    PageType = StandardDialog;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(Document)
            {
                Caption = 'Belge';
                field(DocumentType; DocType)
                {
                    ApplicationArea = All;
                    Caption = 'Belge Türü';
                    ToolTip = 'Satış/satınalma/transfer siparişi, ambar belgesi veya kaydedilmiş belge.';
                }
                field(DocumentNo; DocNo)
                {
                    ApplicationArea = All;
                    Caption = 'Belge No.';
                    ToolTip = 'Satırları LP''ye çekilecek belgenin numarası.';
                }
            }
        }
    }

    procedure GetSelection(var SelectedDocType: Enum "DOPSWHS Assigned Doc Type"; var SelectedDocNo: Code[20])
    begin
        SelectedDocType := DocType;
        SelectedDocNo := DocNo;
    end;

    procedure SetDefaults(DefaultDocType: Enum "DOPSWHS Assigned Doc Type"; DefaultDocNo: Code[20])
    begin
        DocType := DefaultDocType;
        DocNo := DefaultDocNo;
    end;

    var
        DocType: Enum "DOPSWHS Assigned Doc Type";
        DocNo: Code[20];
}
