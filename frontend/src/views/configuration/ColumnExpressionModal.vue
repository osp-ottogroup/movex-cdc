<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">Column Expressions ({{ operation }})</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-table :data="expressions" :striped="true" :hoverable="true">
          <b-table-column field="sql" label="SQL Expression" v-slot="props">
            <span @click="editExpression(props.row)" style="cursor:pointer; color:#3273dc;">{{ props.row.sql }}</span>
          </b-table-column>
        </b-table>
      </section>
      <footer class="modal-card-foot">
        <b-button type="is-primary" @click="$emit('close')">Close</b-button>
        <b-button type="is-success" @click="openNewExpressionModal">New Expression</b-button>
      </footer>
    </div>
    <edit-column-expression-modal
      :show="editModal.show"
      :expression="editModal.expression"
      @close="closeEditModal"
      @save="saveExpression"
      @remove="removeExpression"
    />
  </b-modal>
</template>

<script>
import EditColumnExpressionModal from './EditColumnExpressionModal.vue';

export default {
  name: 'ColumnExpressionModal',
  components: { EditColumnExpressionModal },
  props: {
    show: Boolean,
    expressions: Array,
    operation: String,
  },
  data() {
    return {
      editModal: {
        show: false,
        expression: {},
      },
    };
  },
  methods: {
    openNewExpressionModal() {
      this.editModal.expression = { sql: '', operation: this.operation };
      this.editModal.show = true;
    },
    editExpression(expr) {
      this.editModal.expression = { ...expr };
      this.editModal.show = true;
    },
    closeEditModal() {
      this.editModal.show = false;
    },
    saveExpression(expr) {
      this.$emit('save-expression', expr);
      this.editModal.show = false;
    },
    removeExpression(expr) {
      this.$emit('remove-expression', expr);
      this.editModal.show = false;
    },
  },
};
</script>
