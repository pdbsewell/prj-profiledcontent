import { LightningElement } from 'lwc';

var syntheticClick = false;

export default class PcgDealerFilter extends LightningElement {
    renderedCallback() {
        this.template.querySelector('[data-id="dealerfilter"]').addEventListener('keyup',
            this.delay(function (e) {
                // console.log('Keyup:', this.value);
                syntheticClick = true;
                this.click();
            }, 500)) 

    }

    onclickHandler(event) {
        if (syntheticClick) {
            // console.log('synthetic click! filter is:' + event.target.value);
            syntheticClick = false;
            if (event.target.value.length > 0) {
                // console.log('Sending filter change event');
                const filterChangeEvent = new CustomEvent('filterchange', {
                    detail: event.target.value
                });
                this.dispatchEvent(filterChangeEvent);
            } 
        } else {
            // console.log('real click!');
        }
    }

    onchangeHandler(event) {
        if (event.target.value.length == 0) {
            // console.log('Sending filter reset event');
            let filter = '';
            const filterChangeEvent = new CustomEvent('filterchange', {
                detail: filter
            });
            this.dispatchEvent(filterChangeEvent);
        } 
    }

    delay(callback, ms) {
        var timer = 0;
        return function() {
            var context = this, args = arguments;
            clearTimeout(timer);
            timer = setTimeout(function () {
                callback.apply(context, args);
            }, ms || 0);
        };
    }

}