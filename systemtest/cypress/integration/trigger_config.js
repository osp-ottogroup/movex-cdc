describe('Users', () => {
    beforeEach(() => {
        cy.login('admin', 'test')
    })

    it('Switch Triggers', () => {
        // TODO How to deal with testdata? Options:
        //  - make tests flexible (to react dynamically on given situation)
        //  - let tests prepare data (via frontend)
        //  - populate testdata via db or api
        cy.visit('/configuration')
        cy.contains('td', 'created_at').parent().as('row')

        cy.get('@row').find('.switch').eq(0).click()
        const toastText = 'Saved changes to column \'created_at\'!';
        cy.contains('div', toastText)
        cy.get('div', {timeout: 10000}).contains(toastText).should('not.exist')

        cy.get('@row').find('.switch').eq(1).click()
        cy.contains('div', toastText)
        cy.get('div', {timeout: 10000}).contains(toastText).should('not.exist')

        cy.get('@row').find('.switch').eq(2).click()
        cy.contains('div', toastText)
        cy.get('div', {timeout: 10000}).contains(toastText).should('not.exist')
    })

})