CREATE TABLE uk_price_paid                                                                                                                                                                   (
   id serial primary key,
   price INTEGER,
   date Date,
   postcode1 varchar(8),
   postcode2 varchar(3),
   type varchar(13),
   is_new SMALLINT,
   duration varchar(9),
   addr1 varchar(100),
   addr2 varchar(100),
   street varchar(60),
   locality varchar(35),
   town varchar(35),
   district varchar(40),
   county varchar(35)
)
