enum 72219 "DOPSWHS EDesp Run Mode"
{
    Extensible = false;
    Caption = 'E-Despatch Provider Step';

    value(0; CreateDraft) { Caption = 'Create Draft'; }
    value(1; UpdateDraft) { Caption = 'Update Draft'; }
    value(2; Submit) { Caption = 'Submit'; }
    value(3; RefreshStatus) { Caption = 'Refresh Status'; }
}
