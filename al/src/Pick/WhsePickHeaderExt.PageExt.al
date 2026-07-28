pageextension 72311 "DOPSWHS Whse Pick Header Ext" extends "Warehouse Pick"
{
    layout
    {
        addlast(General)
        {
            field("DOPSWHS Assigned User"; Rec."Assigned User ID")
            {
                ApplicationArea = All;
                Caption = 'Assigned User';
                ToolTip = 'Specifies the WMS operator assigned to this pick. Pick a WMS user from the lookup; warehouse-employee validation is skipped so operators without a Warehouse Employee record can be assigned.';
                // "Assigned User ID" alanının TableRelation'ı Warehouse Employee.
                // WMS operatörleri (DOPSWHS Local User) her zaman Warehouse
                // Employee değil; standart Validate atamayı sessizce geri
                // alıyordu (kullanıcı yazıyor, kaydedince alan boşalıyordu).
                // Bu yüzden lookup WMS kullanıcı listesinden yapılır ve değer
                // Validate tetiklemeden doğrudan yazılır.
                TableRelation = "DOPSWHS Local User".Username;
                ValidateTableRelation = false;
                LookupPageId = "DOPSWHS Local User List";

                trigger OnValidate()
                var
                    PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                begin
                    // Geçmiş kaydı + webhook için codeunit üzerinden yaz.
                    if Rec."Assigned User ID" <> '' then
                        PickMgmt.ReassignPick(Rec, Rec."Assigned User ID", 'Assigned from pick card');
                end;
            }
            field("DOPSWHS Vehicle No."; Rec."DOPSWHS Vehicle No.")
            {
                ApplicationArea = All;
                Caption = 'Vehicle No.';
                ToolTip = 'Specifies the vehicle (forklift/pallet truck) assigned to this pick. Entered by the desk supervisor; shown read-only on the handheld.';
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
                action("DOPSWHS Start Shipping LP")
                {
                    ApplicationArea = All;
                    Caption = 'Start Shipping LP';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                    begin
                        Message('Started LP %1.', PickMgmt.StartShippingLP(Rec, 'PALLET-EUR'));
                    end;
                }
                action("DOPSWHS Stop Shipping LP")
                {
                    ApplicationArea = All;
                    Caption = 'Stop Shipping LP';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                        LP: Record "DOPSWHS LP Header";
                        LpNo: Code[20];
                    begin
                        if Page.RunModal(Page::"DOPSWHS LP List", LP) <> Action::LookupOK then
                            exit;
                        LpNo := LP."No.";
                        Message('SSCC %1.', PickMgmt.StopShippingLP(Rec, LpNo, true));
                    end;
                }
                action("DOPSWHS Reassign to User")
                {
                    ApplicationArea = All;
                    Caption = 'Assign to WMS Operator';
                    Image = AssignItemCharge;
                    Promoted = true;
                    PromotedCategory = Process;
                    ToolTip = 'Assigns this pick to a WMS operator. The list shows local WMS users (the accounts operators sign in with on the handheld), not Business Central users.';
                    trigger OnAction()
                    var
                        PickMgmt: Codeunit "DOPSWHS Pick Mgmt";
                        LocalUser: Record "DOPSWHS Local User";
                    begin
                        // Terminal operatörleri BC kullanıcısı değil, "DOPSWHS
                        // Local User" kaydıdır. Eskiden BC User Lookup açılıyordu;
                        // seçilen BC kullanıcısı terminaldeki operatörle eşleşmediği
                        // için atama terminalde görünmüyordu.
                        LocalUser.SetRange(Disabled, false);
                        if Page.RunModal(Page::"DOPSWHS Local User List", LocalUser) <> Action::LookupOK then
                            exit;
                        PickMgmt.ReassignPick(Rec, LocalUser.Username, 'Assigned from pick card');
                        CurrPage.Update(false);
                        Message('Pick %1 assigned to %2.', Rec."No.", LocalUser."Display Name");
                    end;
                }
                action("DOPSWHS Mark Short")
                {
                    ApplicationArea = All;
                    Caption = 'Mark Short';
                    trigger OnAction()
                    begin
                        Page.Run(Page::"DOPSWHS Short Pick Reason List");
                    end;
                }
            }
        }
    }
}
