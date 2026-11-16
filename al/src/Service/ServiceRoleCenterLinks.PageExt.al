// Puts "Service Management" on the role centers service offices actually use, so nobody has to
// search for it. Role centers cannot run code, so the links use the custom application area
// DOPSWHSService ("DOPSWHS Service App Area"): it is on only while Service Terminal Setup is
// enabled, which keeps warehouse-only customers on the same BASE build unaffected.
pageextension 72120 "DOPSWHS Svc Business Mgr RC" extends "Business Manager Role Center"
{
    actions
    {
        addlast(Embedding)
        {
            action(DOPSWHSServiceBoard)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Management';
                Image = ServiceSetup;
                RunObject = page "DOPSWHS Service Board";
                ToolTip = 'Open the service board: open jobs, technician assignment and technician workload.';
            }
        }
        addlast(Sections)
        {
            group(DOPSWHSService)
            {
                Caption = 'Service';
                action(DOPSWHSServiceBoard2)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Management';
                    RunObject = page "DOPSWHS Service Board";
                }
                action(DOPSWHSServiceOrders)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Orders';
                    RunObject = page "Service Orders";
                }
                action(DOPSWHSServiceItems)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Items';
                    RunObject = page "Service Item List";
                }
                action(DOPSWHSPostedShipments)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Posted Service Shipments';
                    RunObject = page "Posted Service Shipments";
                }
                action(DOPSWHSPostedInvoices)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Posted Service Invoices';
                    RunObject = page "Posted Service Invoices";
                }
                action(DOPSWHSTechnicians)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Technicians';
                    RunObject = page "DOPSWHS Service Technicians";
                }
                action(DOPSWHSServiceSetup)
                {
                    ApplicationArea = DOPSWHSService;
                    Caption = 'Service Terminal Setup';
                    RunObject = page "DOPSWHS Service Setup";
                }
            }
        }
    }

}

pageextension 72121 "DOPSWHS Svc Dispatcher RC" extends "Service Dispatcher Role Center"
{
    actions
    {
        addfirst(Embedding)
        {
            action(DOPSWHSServiceBoard)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Management';
                Image = ServiceSetup;
                RunObject = page "DOPSWHS Service Board";
                ToolTip = 'Open the service board: open jobs, technician assignment and technician workload.';
            }
            action(DOPSWHSTechnicians)
            {
                ApplicationArea = DOPSWHSService;
                Caption = 'Service Technicians';
                RunObject = page "DOPSWHS Service Technicians";
            }
        }
    }

}
