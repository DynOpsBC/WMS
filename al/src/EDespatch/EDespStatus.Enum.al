enum 72215 "DOPSWHS EDesp Status"
{
    Extensible = true;
    Caption = 'E-Despatch Request Status';

    value(0; Pending) { Caption = 'Pending'; }
    value(1; Draft) { Caption = 'Draft'; }
    value(2; Sending) { Caption = 'Sending'; }
    value(3; Sent) { Caption = 'Sent'; }
    value(4; Accepted) { Caption = 'Accepted'; }
    value(5; Rejected) { Caption = 'Rejected'; }
    value(6; Cancelled) { Caption = 'Cancelled'; }
    value(7; Error) { Caption = 'Error'; }
    value(8; WaitingAdapter) { Caption = 'Waiting for Provider'; }
    value(9; NotRequired) { Caption = 'Not Required'; }
}
