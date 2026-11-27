enum 72216 "DOPSWHS EDesp Receiver Type"
{
    Extensible = false;
    Caption = 'E-Despatch Receiver Type';

    // Same order as the receiver type of the e-transformation app, so the connector can map by ordinal.
    value(0; " ") { Caption = 'Resolve Automatically'; }
    value(1; OwnCompany) { Caption = 'Own Company'; }
    value(2; Vendor) { Caption = 'Vendor'; }
    value(3; Customer) { Caption = 'Customer'; }
}
