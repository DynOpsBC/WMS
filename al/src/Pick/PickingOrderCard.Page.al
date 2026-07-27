page 72356 "DOPSWHS Picking Order Card"
{
    PageType = Card;
    Caption = 'Toplanacak Siparişler';
    SourceTable = "DOPSWHS Picking Order Header";
    ApplicationArea = All;
    UsageCategory = Tasks;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; Editable = false; }
                field(Description; Rec.Description) { ApplicationArea = All; Editable = Rec.Status = Rec.Status::Open; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Editable = Rec.Status = Rec.Status::Open; }
                field("Assigned User ID"; Rec."Assigned User ID") { ApplicationArea = All; Editable = Rec.Status = Rec.Status::Open; ToolTip = 'Leave blank so the picker can use Kendime Ata on the handheld.'; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Warehouse Pick No."; Rec."Warehouse Pick No.") { ApplicationArea = All; }
                field("Warehouse Shipment No."; Rec."Warehouse Shipment No.") { ApplicationArea = All; }
            }
            part(Lines; "DOPSWHS Picking Order Lines")
            {
                ApplicationArea = All;
                SubPageLink = "Header Entry No." = field("Entry No.");
                UpdatePropagation = Both;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(SelectSalesOrders)
            {
                Caption = 'Satış Siparişlerini Seç';
                ApplicationArea = All;
                Image = SelectEntries;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Open;

                trigger OnAction()
                var
                    SalesHeader: Record "Sales Header";
                    SalesOrderList: Page "Sales Order List";
                    PickingOrderMgmt: Codeunit "DOPSWHS Picking Order Mgmt";
                begin
                    // ELOG "toplanacak siparişler": yalnızca OPS Status = Pending ve
                    // açık pick'i olmayan siparişler seçilebilir (BADE akışı Pending
                    // üzerinden yürür; Released şartı yok — çoğu sipariş Open).
                    // Refunded/Canceled/Returned OPS Status'leri ve zaten toplanmışlar gizlenir.
                    SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Order);
                    PickingOrderMgmt.ApplyOpsPendingFilter(SalesHeader);
                    PickingOrderMgmt.FilterToPickable(SalesHeader);
                    SalesOrderList.SetTableView(SalesHeader);
                    SalesOrderList.LookupMode(true);
                    if SalesOrderList.RunModal() = Action::LookupOK then begin
                        SalesOrderList.SetSelectionFilter(SalesHeader);
                        PickingOrderMgmt.AddSelectedOrders(Rec, SalesHeader);
                        CurrPage.Update(false);
                    end;
                end;
            }
            action(PostPick)
            {
                Caption = 'Pick Oluştur / Post Et';
                ApplicationArea = All;
                Image = CreateMovement;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Enabled = Rec.Status = Rec.Status::Open;

                trigger OnAction()
                var
                    PickingOrderMgmt: Codeunit "DOPSWHS Picking Order Mgmt";
                    PickNo: Code[20];
                begin
                    PickNo := PickingOrderMgmt.PostPickingOrder(Rec);
                    Message('Warehouse Pick %1 created. It is now visible on the handheld.', PickNo);
                    CurrPage.Update(false);
                end;
            }
            action(OpenWarehousePick)
            {
                Caption = 'Warehouse Pick Aç';
                ApplicationArea = All;
                Image = Open;
                Enabled = Rec."Warehouse Pick No." <> '';

                trigger OnAction()
                var
                    PickHeader: Record "Warehouse Activity Header";
                begin
                    PickHeader.Get(PickHeader.Type::Pick, Rec."Warehouse Pick No.");
                    Page.Run(Page::"Warehouse Pick", PickHeader);
                end;
            }
        }
    }
}
