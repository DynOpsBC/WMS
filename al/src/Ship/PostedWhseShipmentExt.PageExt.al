pageextension 72317 "DOPSWHS Posted Whse Shpt Ext" extends "Posted Whse. Shipment"
{
    layout
    {
        addlast(General)
        {
            field("DOPSWHS Container No."; Rec."DOPSWHS Container No.")
            {
                ApplicationArea = All;
                Caption = 'Konteyner No.';
                Editable = false;
            }
            field("DOPSWHS Seal No."; Rec."DOPSWHS Seal No.")
            {
                ApplicationArea = All;
                Caption = 'Mühür No.';
                Editable = false;
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            action("DOPSWHS Packing List")
            {
                ApplicationArea = All;
                Caption = 'Paketleme Listesi';
                ToolTip = 'Kaydedilmiş sevkiyatın palet/koli/kutu paketleme listesi.';
                Image = PrintReport;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                var
                    PackingList: Codeunit "DOPSWHS Packing List Mgt.";
                begin
                    PackingList.RunForShipment(true, Rec."No.");
                end;
            }
        }
    }
}
