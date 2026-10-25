-- What correct-database exists to repair, written as an older version or a bad import leaves it:
-- two groceries whose destination side no longer matches the source (an uneven journal), and the
-- rent paid to the employer's revenue account (a withdrawal whose destination has the wrong type).
update transactions set amount = '40.00' where id = (select t.id from transactions t join transaction_journals j on j.id = t.transaction_journal_id where j.description = 'Groceries' and t.amount > 0 order by t.id limit 1);
update transactions set amount = '60.00' where id = (select t.id from transactions t join transaction_journals j on j.id = t.transaction_journal_id where j.description = 'Groceries' and t.amount > 0 order by t.id limit 1 offset 1);
update transactions set account_id = (select id from accounts where name = 'Employer') where id = (select t.id from transactions t join transaction_journals j on j.id = t.transaction_journal_id where j.description = 'Rent' and t.amount > 0);
