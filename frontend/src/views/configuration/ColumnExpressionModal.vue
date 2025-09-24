<template>
  <b-modal :active="show" @close="$emit('close')">
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">Column Expressions ({{ operation }})</p>
        <button class="delete" @click="$emit('close')"></button>
      </header>
      <section class="modal-card-body">
        <b-table :data="localExpressions" :striped="true" :hoverable="true">
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
import CRUDService from '@/services/CRUDService';
import EditColumnExpressionModal from './EditColumnExpressionModal.vue';

export default {
  name: 'ColumnExpressionModal',
  components: { EditColumnExpressionModal },
  props: {
    show: Boolean,
    expressions: Array,
    operation: String,
    tableId: [String, Number],
  },
  data() {
    return {
      localExpressions: [],
      editModal: {
        show: false,
        expression: {},
      },
    };
  },
  watch: {
    expressions: {
      immediate: true,
      handler(newVal) {
        this.localExpressions = [...newVal];
      },
    },
    operation: {
      immediate: true,
      handler() {
        this.reloadExpressions();
      },
    },
    show(val) {
      if (val) this.reloadExpressions();
    },
  },
  methods: {
    async reloadExpressions() {
      if (!this.tableId || !this.operation) return;
      try {
        const allExpr = await CRUDService.columnExpressions.getAll({ table_id: this.tableId });
        this.localExpressions = allExpr.filter((e) => e.operation === this.operation);
      } catch (e) {
        // Fehlerbehandlung optional
      }
    },
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
    async saveExpression(expr) {
      const newExpr = { ...expr };
      if (!newExpr.table_id) {
        newExpr.table_id = this.tableId;
      }
      this.$emit('save-expression', newExpr);
      this.editModal.show = false;
      await this.reloadExpressions();
    },
    async removeExpression(expr) {
      const newExpr = { ...expr };
      this.$emit('remove-expression', newExpr);
      this.editModal.show = false;
      await this.reloadExpressions();
    },
  },
};
</script>
