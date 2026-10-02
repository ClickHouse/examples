const form=document.querySelector('.invoice-editor');
if(form) {
  const container=form.querySelector('[data-lines]');
  const renumber=()=>container.querySelectorAll('[data-line]').forEach((row,index)=>{
    row.querySelector('legend').textContent=`Line ${index+1}`;
    row.querySelectorAll('[data-field]').forEach(input=>{
      input.name=`lines[${index}][${input.dataset.field}]`; input.id=`${input.dataset.field}-${index}`;
      input.previousElementSibling.htmlFor=input.id;
    });
  });
  form.querySelector('[data-add]').addEventListener('click',()=>{
    if(container.children.length>=100) return;
    const row=container.firstElementChild.cloneNode(true);
    row.querySelectorAll('input').forEach(input=>input.value=input.dataset.field==='quantity'?'1':input.dataset.field==='unit_price'?'0.00':'');
    container.append(row);renumber();
  });
  container.addEventListener('click',event=>{
    if(event.target.matches('[data-remove]') && container.children.length>1) {event.target.closest('[data-line]').remove();renumber();}
  });
}
