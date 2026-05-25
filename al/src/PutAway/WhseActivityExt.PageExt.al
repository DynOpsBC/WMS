pageextension 72306 "DOPSWHS Whse Activity Ext" extends "Whse. Activity"
{
    layout
    {
        addlast(FactBoxes)
        {
            part("DOPSWHS Assigned User"; "User Card Part")
            {
                ApplicationArea = All;
                Caption = 'Assigned User';
                SubPageLink = "User Name" = field("Assigned User ID");
                Visible = IsMobileFactBoxVisible;
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
                Image = Warehouse;

                action(SuggestBin)
                {
                    ApplicationArea = All;
                    Caption = 'Suggest Bin';
                    Image = Suggest;
                    Visible = IsPutAwayVisible;

                    trigger OnAction()
                    var
                        WhseActivityLine: Record "Warehouse Activity Line";
                        DirectedPutAway: Codeunit "DOPSWHS Directed PutAway";
                        Item: Record Item;
                        BinCode: Code[20];
                        Reason: Text;
                    begin
                        WhseActivityLine.SetRange("Activity Type", Rec.Type);
                        WhseActivityLine.SetRange("No.", Rec."No.");
                        if WhseActivityLine.FindFirst() then begin
                            Item.Get(WhseActivityLine."Item No.");
                            if DirectedPutAway.SuggestBin(Item, WhseActivityLine."Qty. to Handle", Rec."Location Code", BinCode, Reason) then
                                Message('Suggested bin: %1', BinCode)
                            else
                                Message(Reason);
                        end;
                    end;
                }

                action(RegisterActivity)
                {
                    ApplicationArea = All;
                    Caption = 'Register Activity';
                    Image = Register;
                    Visible = IsRegisterVisible;

                    trigger OnAction()
                    var
                        MovementMgmt: Codeunit "DOPSWHS Movement Mgmt";
                    begin
                        MovementMgmt.RegisterDirected(Rec);
                    end;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        IsPutAwayVisible := Rec.Type = Rec.Type::"Put-away";
        IsRegisterVisible := Rec.Type in [Rec.Type::"Put-away", Rec.Type::Movement];
        IsMobileFactBoxVisible := Rec.Type in [Rec.Type::"Put-away", Rec.Type::Pick, Rec.Type::Movement];
    end;

    var
        IsPutAwayVisible: Boolean;
        IsRegisterVisible: Boolean;
        IsMobileFactBoxVisible: Boolean;
}
