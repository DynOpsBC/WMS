/// Admin-only preparation; terminals use the read-only API and never need to import a file.
page 72201 "DOPSWHS Prepared Label Setup"
{
    PageType = Card;
    SourceTable = Integer;
    SourceTableTemporary = true;
    ApplicationArea = All;
    Caption = 'Hazır Etiket Listesi';
    layout
    {
        area(Content)
        {
            group(General)
            {
                field(ListCode; ListCode) { ApplicationArea = All; Caption = 'Liste Kodu'; }
                field(SourceDate; SourceDate) { ApplicationArea = All; Caption = 'Kaynak Tarihi'; }
                field(RowsJson; RowsJson) { ApplicationArea = All; Caption = 'Liste Satırları (JSON)'; MultiLine = true; }
                field(ImportedCount; ImportedCount) { ApplicationArea = All; Caption = 'Kayıtlı Satır'; Editable = false; }
            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(SaveList)
            {
                ApplicationArea = All;
                Caption = 'Etiket Listesini Kaydet';
                Image = Save;
                trigger OnAction()
                var
                    Mgmt: Codeunit "DOPSWHS Prepared Label Mgmt";
                begin
                    ImportedCount := Mgmt.ReplaceList(ListCode, SourceDate, RowsJson);
                    RowsJson := '';
                    CurrPage.Update(false);
                    Message('%1 satır kaydedildi. Yazdırma işi oluşturulmadı.', ImportedCount);
                end;
            }
            action(ViewList)
            {
                ApplicationArea = All;
                Caption = 'Kayıtlı Listeyi Görüntüle';
                Image = View;
                trigger OnAction()
                var
                    Mgmt: Codeunit "DOPSWHS Prepared Label Mgmt";
                begin
                    RowsJson := Mgmt.ExportList(ListCode);
                end;
            }
        }
    }
    var
        ListCode: Code[20];
        SourceDate: Date;
        RowsJson: Text;
        ImportedCount: Integer;
    trigger OnOpenPage()
    var
        Rows: Record "DOPSWHS Prepared Label Row";
    begin
        Rec.Number := 1;
        Rec.Insert();
        ListCode := 'DKC-GOZ-20261015';
        SourceDate := DMY2Date(15, 10, 2026);
        Rows.SetRange("List Code", ListCode);
        ImportedCount := Rows.Count();
    end;
}
