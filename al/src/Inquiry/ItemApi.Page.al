page 72086 "DOPSWHS Item API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'item';
    EntitySetName = 'items';
    SourceTable = Item;
    DelayedInsert = true;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec.Description) { Caption = 'description'; }
                field(baseUnitOfMeasure; Rec."Base Unit of Measure") { Caption = 'baseUnitOfMeasure'; }
                field(itemCategoryCode; Rec."Item Category Code") { Caption = 'itemCategoryCode'; }
                field(blocked; Rec.Blocked) { Caption = 'blocked'; }
                field(defaultLpTemplateCode; Rec."DOPSWHS Default LP Template") { Caption = 'defaultLpTemplateCode'; }
                field(defaultPrintRuleCode; Rec."DOPSWHS Default Print Rule") { Caption = 'defaultPrintRuleCode'; }
                // PDF feedback (Item Inquiry section 1): clients reported
                // "stok yok" because Inventory FlowField was missing.
                // Exposes the standard Inventory + on-order quantities so
                // mobile/web can render a real stock card.
                field(inventory; Rec.Inventory)
                {
                    Caption = 'inventory';
                    Editable = false;
                }
                field(quantityOnPurchOrder; Rec."Qty. on Purch. Order")
                {
                    Caption = 'quantityOnPurchOrder';
                    Editable = false;
                }
                field(quantityOnSalesOrder; Rec."Qty. on Sales Order")
                {
                    Caption = 'quantityOnSalesOrder';
                    Editable = false;
                }
                field(quantityOnProdOrder; Rec."Qty. on Prod. Order")
                {
                    Caption = 'quantityOnProdOrder';
                    Editable = false;
                }
                field(reservedQtyOnInventory; Rec."Reserved Qty. on Inventory")
                {
                    Caption = 'reservedQtyOnInventory';
                    Editable = false;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        // FlowField'lar API page'inde otomatik hesaplanmaz; explicit CalcFields
        // çağrılmazsa response'da Inventory=0 döner ve Item Inquiry "stok yok"
        // göstermeye devam eder (Codex review Finding 6).
        Rec.CalcFields(
            Inventory,
            "Qty. on Purch. Order",
            "Qty. on Sales Order",
            "Qty. on Prod. Order",
            "Reserved Qty. on Inventory");
    end;
}
