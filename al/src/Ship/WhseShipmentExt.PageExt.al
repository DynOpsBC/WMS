pageextension 72307 "DOPSWHS Whse Shipment Ext" extends "Warehouse Shipment"
{
    layout
    {
        addlast(General)
        {
            field("DOPSWHS Container No."; Rec."DOPSWHS Container No.")
            {
                ApplicationArea = All;
                Caption = 'Konteyner No.';
                ToolTip = 'Paketleme listesinin başlığında basılır; kayıtta posted sevkiyata taşınır.';
            }
            field("DOPSWHS Seal No."; Rec."DOPSWHS Seal No.")
            {
                ApplicationArea = All;
                Caption = 'Mühür No.';
                ToolTip = 'Paketleme listesinin başlığında basılır.';
            }
        }
        addlast(FactBoxes)
        {
            part("DOPSWHS Shipping LPs"; "DOPSWHS Shipment LP Factbox")
            {
                ApplicationArea = All;
                Caption = 'Shipping LPs';
                SubPageLink = "Assigned Document Type" = const(WhseShipment), "Assigned Document No." = field("No.");
            }
        }
    }

    actions
    {
        addlast(Processing)
        {
            group("DOPSWHS Mobile")
            {
                Caption = 'DOPSWHS Mobile';

                action("DOPSWHS Post Mobile")
                {
                    ApplicationArea = All;
                    Caption = 'Post Mobile';
                    Image = PostDocument;

                    trigger OnAction()
                    var
                        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
                    begin
                        ShipmentMgmt.PostShipment(Rec, false, false);
                    end;
                }
                action("DOPSWHS Print Packing Slip")
                {
                    ApplicationArea = All;
                    Caption = 'Print Packing Slip';
                    Image = Print;

                    trigger OnAction()
                    var
                        ShipmentMgmt: Codeunit "DOPSWHS Shipment Mgmt";
                    begin
                        ShipmentMgmt.PostShipment(Rec, true, false);
                    end;
                }
                action("DOPSWHS Packing List")
                {
                    ApplicationArea = All;
                    Caption = 'Paketleme Listesi';
                    ToolTip = 'Sevkiyattaki paletlerin koli/kutu hiyerarşisini, SSCC ve ağırlıklarını listeler (kayıttan önce önizleme).';
                    Image = PrintReport;

                    trigger OnAction()
                    var
                        PackingList: Codeunit "DOPSWHS Packing List Mgt.";
                    begin
                        PackingList.RunForShipment(false, Rec."No.");
                    end;
                }
            }
        }
    }
}
