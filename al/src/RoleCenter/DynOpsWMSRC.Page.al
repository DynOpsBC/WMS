page 72095 "DOPSWHS DynOps WMS RC"
{
    Caption = 'DynOps Warehouse Management';
    PageType = RoleCenter;
    ApplicationArea = All;

    layout
    {
        area(RoleCenter)
        {
            part(Activities; "DOPSWHS DynOps WMS Activities")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        // ============================================
        // EMBED ACTIONS — burası RC içindeki "Sections" navigation menüsü
        // ============================================
        area(Sections)
        {
            group(MalKabulNav)
            {
                Caption = '📥 Mal Kabul';
                action(WhseReceiptsNav) { Caption = 'Açık Mal Kabul'; ApplicationArea = All; RunObject = page "Warehouse Receipts"; }
                action(ReceivingQueueNav) { Caption = 'Mal Kabul Kuyruğu'; ApplicationArea = All; RunObject = page "DOPSWHS Receiving Queue"; }
                action(POListNav) { Caption = 'Sipariş Listesi (PO)'; ApplicationArea = All; RunObject = page "Purchase Order List"; }
                action(TransferInNav) { Caption = 'Transfer Orderlar'; ApplicationArea = All; RunObject = page "Transfer Orders"; }
            }
            group(YerlestirmeNav)
            {
                Caption = '📦 Yerleştirme';
                action(WhsePutAwayNav) { Caption = 'Warehouse Put-Away'; ApplicationArea = All; RunObject = page "Warehouse Put-aways"; }
                action(InvtPutAwayNav) { Caption = 'Inventory Put-Away'; ApplicationArea = All; RunObject = page "Inventory Put-aways"; }
            }
            group(ToplamaNav)
            {
                Caption = '🚚 Toplama';
                action(WhsePicksNav) { Caption = 'Warehouse Picks'; ApplicationArea = All; RunObject = page "Warehouse Picks"; }
                action(InvtPicksNav) { Caption = 'Inventory Picks'; ApplicationArea = All; RunObject = page "Inventory Picks"; }
                action(PickQueueNav) { Caption = 'Pick Kuyruğu (Drag-Drop)'; ApplicationArea = All; RunObject = page "DOPSWHS Pick Queue"; }
                action(ShortPickReasonNav) { Caption = 'Short Pick Reasons'; ApplicationArea = All; RunObject = page "DOPSWHS Short Pick Reason List"; }
            }
            group(SevkiyatNav)
            {
                Caption = '📤 Sevkiyat';
                action(WhseShipmentsNav) { Caption = 'Warehouse Shipments'; ApplicationArea = All; RunObject = page "Warehouse Shipment List"; }
                action(ShipmentQueueNav) { Caption = 'Sevkiyat Kuyruğu'; ApplicationArea = All; RunObject = page "DOPSWHS Shipment Queue"; }
                action(SalesOrdersNav) { Caption = 'Sales Orders'; ApplicationArea = All; RunObject = page "Sales Order List"; }
            }
            group(HareketlerNav)
            {
                Caption = '🔄 Hareketler';
                // TODO Sprint H+ post-deploy: bind to "Warehouse Movements" once standard BC page name resolves in target symbols.
                action(WhseMovementsNav) { Caption = 'Warehouse Movements (Activity)'; ApplicationArea = All; RunObject = page "Warehouse Activity List"; }
                action(ItemReclassNav) { Caption = 'Item Reclass. Journal (Ad-Hoc)'; ApplicationArea = All; RunObject = page "Item Reclass. Journal"; }
            }
            group(UretimNav)
            {
                Caption = '🏭 Üretim & Montaj';
                action(ReleasedProdOrdersNav) { Caption = 'Released Production Orders'; ApplicationArea = All; RunObject = page "Released Production Orders"; }
                action(AssemblyOrdersNav) { Caption = 'Assembly Orders'; ApplicationArea = All; RunObject = page "Assembly Orders"; }
            }
            group(LPNav)
            {
                Caption = '🏷️ License Plate';
                action(LPListNav) { Caption = 'LP List'; ApplicationArea = All; RunObject = page "DOPSWHS LP List"; }
                action(LPTemplateNav) { Caption = 'LP Templates'; ApplicationArea = All; RunObject = page "DOPSWHS LP Template List"; }
                action(LPMovLedgerNav) { Caption = 'LP Movement Ledger'; ApplicationArea = All; RunObject = page "DOPSWHS LP Movement Ledger"; }
            }
            group(SayimNav)
            {
                Caption = '📊 Sayım';
                action(CountSheetsNav) { Caption = 'Count Sheets'; ApplicationArea = All; RunObject = page "DOPSWHS Count Sheet List"; }
                action(PhysInvJournalNav) { Caption = 'Physical Inventory Journal'; ApplicationArea = All; RunObject = page "Phys. Inventory Journal"; }
            }
            group(SistemNav)
            {
                Caption = '⚙️ Sistem Yönetimi';
                action(SetupNav) { Caption = 'BCWMSApp Setup'; ApplicationArea = All; RunObject = page "DOPSWHS Setup"; }
                action(DeviceConfigNav) { Caption = 'Device Configuration'; ApplicationArea = All; RunObject = page "DOPSWHS Device Config List"; }
                action(DeviceRegistrationNav) { Caption = 'Device Registration'; ApplicationArea = All; RunObject = page "DOPSWHS Device Reg List"; }
                action(BarcodeRulesNav) { Caption = 'Barcode Rules'; ApplicationArea = All; RunObject = page "DOPSWHS Barcode Rule List"; }
                action(SymbologyNav) { Caption = 'Barcode Symbologies'; ApplicationArea = All; RunObject = page "DOPSWHS Symbology List"; }
                action(IWXReportSelNav) { Caption = 'IWX Report Selection'; ApplicationArea = All; RunObject = page "DOPSWHS IWX Report Selection"; }
                action(PrintJobLogNav) { Caption = 'Print Job Log'; ApplicationArea = All; RunObject = page "DOPSWHS Print Job Log"; }
                action(SyncConflictNav) { Caption = 'Sync Conflicts'; ApplicationArea = All; RunObject = page "DOPSWHS Sync Conflict List"; }
            }
        }

        // ============================================
        // SHORTCUT ACTIONS — RC üst banner'da promoted
        // ============================================
        area(Embedding)
        {
            action(NewLPShortcut)
            {
                Caption = '+ Yeni LP';
                ApplicationArea = All;
                RunObject = page "DOPSWHS LP Card";
                RunPageMode = Create;
                Image = NewItem;
            }
            action(NewCountSheetShortcut)
            {
                Caption = '+ Yeni Sayım';
                ApplicationArea = All;
                RunObject = page "DOPSWHS Count Sheet Card";
                RunPageMode = Create;
                Image = Inventory;
            }
            action(QuickMoveShortcut)
            {
                Caption = '🔄 Hızlı Bin-to-Bin';
                ApplicationArea = All;
                RunObject = page "Item Reclass. Journal";
                Image = TransferOrder;
            }
            action(ItemInquiryShortcut)
            {
                Caption = '🔎 Item Inquiry';
                ApplicationArea = All;
                RunObject = page "Item List";
                Image = Item;
            }
            action(BinInquiryShortcut)
            {
                Caption = '📍 Bin Inquiry';
                ApplicationArea = All;
                RunObject = page "Bin Contents List";
                Image = Bin;
            }
            action(SetupWizardShortcut)
            {
                Caption = '⚙️ Setup';
                ApplicationArea = All;
                RunObject = page "DOPSWHS Setup";
                Image = Setup;
            }
        }

        // ============================================
        // PROMOTED — header'da görünen ana action bar
        // ============================================
        area(Processing)
        {
            group(QuickActions)
            {
                Caption = 'Hızlı İşlemler';
                action(NewLPPromoted)
                {
                    Caption = '+ Yeni LP';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS LP Card";
                    RunPageMode = Create;
                    Image = NewItem;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                }
                action(NewCountSheetPromoted)
                {
                    Caption = '+ Yeni Sayım Sayfası';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS Count Sheet Card";
                    RunPageMode = Create;
                    Image = Inventory;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                }
                action(QuickMovePromoted)
                {
                    Caption = 'Hızlı Bin-to-Bin Hareket';
                    ApplicationArea = All;
                    RunObject = page "Item Reclass. Journal";
                    Image = TransferOrder;
                    Promoted = true;
                    PromotedCategory = Process;
                    PromotedIsBig = true;
                }
                action(ItemInquiryPromoted)
                {
                    Caption = 'Item Inquiry';
                    ApplicationArea = All;
                    RunObject = page "Item List";
                    Image = Item;
                    Promoted = true;
                    PromotedCategory = Process;
                }
                action(BinInquiryPromoted)
                {
                    Caption = 'Bin Inquiry';
                    ApplicationArea = All;
                    RunObject = page "Bin Contents List";
                    Image = Bin;
                    Promoted = true;
                    PromotedCategory = Process;
                }
            }
            group(SetupActions)
            {
                Caption = 'Yapılandırma';
                action(SetupPromoted)
                {
                    Caption = 'BCWMSApp Setup';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS Setup";
                    Image = Setup;
                    Promoted = true;
                    PromotedCategory = Category4;
                }
                action(BarcodeRulesPromoted)
                {
                    Caption = 'Barcode Rules';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS Barcode Rule List";
                    Image = BarCode;
                    Promoted = true;
                    PromotedCategory = Category4;
                }
                action(DeviceConfigPromoted)
                {
                    Caption = 'Device Configuration';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS Device Config List";
                    Image = Setup;
                    Promoted = true;
                    PromotedCategory = Category4;
                }
                action(LPTemplatesPromoted)
                {
                    Caption = 'LP Templates';
                    ApplicationArea = All;
                    RunObject = page "DOPSWHS LP Template List";
                    Image = Template;
                    Promoted = true;
                    PromotedCategory = Category4;
                }
            }
        }
    }
}
