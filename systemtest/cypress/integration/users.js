describe('Users', () => {
    beforeEach(() => {
        cy.login('admin','test')
    })

    it('Create User', () => {
        cy.visit('/users')
        cy.get('button').contains('Create User').click()
        const email = 'test' + Math.random() + '@man.man'
        cy.get('.modal-card').within(() => {
            cy.get('input').eq(0).type('testman')
            cy.get('input').eq(1).type('doe')
            cy.get('input').eq(2).type(email)
            cy.get('select').select('main')
            cy.get('button').contains('Create').click()
        })

        cy.get('tr').should('contain', 'testman').and('contain', email)
        cy.get('.navbar-item').find('.mdi').click()
        cy.get('button').contains('Logout').click()

        cy.get('input[type=text]').type(email)
        cy.get('input[type=password]').type('test')
        cy.get('button').click()
        cy.get('.navbar-item',{timeout:10000}).contains('TriXX')
    })

})