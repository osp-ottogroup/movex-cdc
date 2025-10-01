<template>
  <div class="is-relative">
    <b-loading :active="isLoading" :is-full-page="false"></b-loading>
    <column-table v-if="mergedColumns.length > 0"
                  :schema="schema"
                  :table="table"
                  :columns="mergedColumns"
                  :activeConditionTypes="activeConditionTypes"
                  :activeColumnExpressionTypes="activeColumnExpressionTypes"
                  @column-changed="onColumnChanged"
                  @select-all="onSelectAll"
                  @deselect-all="onDeselectAll"
                  @edit-condition="onEditCondition"
                  @edit-column-expression="onEditColumnExpression"
                  @remove-column="onRemoveColumn"/>
    <template v-if="conditionModal.show">
      <condition-modal :condition="conditionModal.condition"
                       @saved="onConditionSaved"
                       @removed="onConditionRemoved"
                       @close="onCloseConditionModal"/>
    </template>
    <template v-if="columnExpressionModal.show">
      <column-expression-modal
        ref="columnExpressionModal"
        :show="columnExpressionModal.show"
        :operation="columnExpressionModal.operation"
        :expressions="columnExpressionModal.expressions"
        :table-id="table.id"
        @close="onCloseColumnExpressionModal"
        @save-expression="onSaveColumnExpression"
        @remove-expression="onRemoveColumnExpression"
      />
    </template>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';
import ColumnTable from './ColumnTable.vue';
import ConditionModal from './ConditionModal.vue';
import ColumnExpressionModal from './ColumnExpressionModal.vue';

export default {
  name: 'ColumnManager',
  components: {
    ColumnTable,
    ConditionModal,
    ColumnExpressionModal,
  },
  props: {
    schema: { type: Object, default: () => {} },
    table: { type: Object, default: () => {} },
  },
  data() {
    return {
      columns: [],
      dbColumns: [],
      mergedColumns: [],
      activeConditionTypes: {},
      activeColumnExpressionTypes: {},
      isLoading: false,
      conditionModal: {
        show: false,
        condition: {},
      },
      columnExpressionModal: {
        show: false,
        operation: '',
        expressions: [],
      },
    };
  },
  methods: {
    mergeColumns() {
      // build a map from db columns with column names as keys
      // and column as value, extended by required fields
      const dbColumnsMap = new Map();
      this.dbColumns.forEach((column) => {
        const fields = {
          table_id: this.table.id,
          info: 'TODO',
          yn_log_insert: 'N',
          yn_log_update: 'N',
          yn_log_delete: 'N',
        };
        dbColumnsMap.set(column.name, { ...column, ...fields });
      });
      // enrich/merge the map column values with currently existing column data
      this.columns.forEach((column) => {
        if (dbColumnsMap.has(column.name)) {
          const current = dbColumnsMap.get(column.name);
          dbColumnsMap.set(column.name, { ...current, ...column });
        } else {
          dbColumnsMap.set(column.name, { ...column, isDeleted: true });
        }
      });

      this.mergedColumns = Array.from(dbColumnsMap.values()).sort((a, b) => {
        const aName = a.name.toUpperCase();
        const bName = b.name.toUpperCase();
        if (aName < bName) { return -1; }
        if (aName > bName) { return 1; }
        return 0;
      });
    },
    async onColumnChanged(column) {
      try {
        this.isLoading = true;
        if (column.id) { // update
          await CRUDService.columns.update(column.id, { column });
        } else { // create
          await CRUDService.columns.create({ column });
        }
        this.$buefy.toast.open({
          message: `Saved changes to column '${column.name}'!`,
          type: 'is-success',
        });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async reload(table) {
      try {
        this.isLoading = true;

        // load db and MOVEX CDC columns and merge them in one object
        this.dbColumns = await CRUDService.dbColumns.getAll({
          table_name: table.name,
          schema_name: this.schema.name,
        });
        this.columns = await CRUDService.columns.getAll({ table_id: table.id });
        this.mergeColumns();

        // load conditions
        const conditions = await CRUDService.conditions.getAll({ table_id: table.id });
        this.activeConditionTypes = {};
        conditions.forEach((condition) => {
          this.$set(this.activeConditionTypes, condition.operation, condition);
        });

        // load all column expressions per table
        const columnExpressions = await CRUDService.columnExpressions.getAll({ table_id: table.id });
        this.activeColumnExpressionTypes = {};
        const result = { I: [], U: [], D: [] };
        columnExpressions.forEach((colExpr) => {
          result[colExpr.operation].push(colExpr);
        });
        this.$set(this.activeColumnExpressionTypes, 'I', result.I);
        this.$set(this.activeColumnExpressionTypes, 'U', result.U);
        this.$set(this.activeColumnExpressionTypes, 'D', result.D);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading columns!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
        // do not show any columns if there is an error by switching to another table
        this.mergedColumns = [];
      } finally {
        this.isLoading = false;
      }
    },
    async onSelectAll(type) {
      try {
        this.isLoading = true;
        await CRUDService.columns.selectAll({ table_id: this.table.id, operation: type });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onDeselectAll(type) {
      try {
        this.isLoading = true;
        await CRUDService.columns.deselectAll({ table_id: this.table.id, operation: type });
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onRemoveColumn(column) {
      try {
        this.isLoading = true;
        await CRUDService.columns.delete(column.id, column);
        await this.reload(this.table);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    onEditCondition(triggerType) {
      const condition = this.activeConditionTypes[triggerType];
      if (condition === undefined) {
        this.conditionModal.condition = {
          operation: triggerType,
          filter: '',
          table_id: this.table.id,
        };
      } else {
        this.conditionModal.condition = condition;
      }
      this.conditionModal.show = true;
    },
    onConditionSaved(condition) {
      this.$set(this.activeConditionTypes, condition.operation, condition);
      this.conditionModal.show = false;
    },
    onConditionRemoved(condition) {
      this.$delete(this.activeConditionTypes, condition.operation);
      this.conditionModal.show = false;
    },
    onCloseConditionModal() {
      this.conditionModal.show = false;
    },
    onEditColumnExpression(triggerType) {
      this.columnExpressionModal.operation = triggerType;
      this.columnExpressionModal.expressions = this.activeColumnExpressionTypes[triggerType] || [];
      this.columnExpressionModal.show = true;
    },
    onCloseColumnExpressionModal() {
      this.columnExpressionModal.show = false;
    },
    async onSaveColumnExpression(expr) {
      this.isLoading = true;
      // Kopie von expr erstellen, um ESLint no-param-reassign zu vermeiden
      const newExpr = { ...expr };
      if (!newExpr.table_id) {
        newExpr.table_id = this.table.id;
      }
      const payload = { column_expression: newExpr };
      try {
        if (newExpr.id) {
          await CRUDService.columnExpressions.update(newExpr.id, payload);
        } else {
          await CRUDService.columnExpressions.create(payload);
        }
        this.$buefy.toast.open({
          message: 'Expression saved!',
          type: 'is-success',
        });
        // inform the modal that an expression was saved and list should be reloaded
        this.$refs.columnExpressionModal.$emit('expression-saved');
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        await this.reload(this.table);
        this.isLoading = false;
      }
    },
    async onRemoveColumnExpression(expr) {
      try {
        this.isLoading = true;
        if (expr.id) {
          await CRUDService.columnExpressions.delete(expr.id, { lock_version: expr.lock_version });
          await this.reload(this.table);
          this.$buefy.toast.open({
            message: 'Expression entfernt!',
            type: 'is-success',
          });
          // inform the modal that an expression was removed and list should be reloaded
          this.$refs.columnExpressionModal.$emit('expression-saved');
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
  watch: {
    async table(newTable, oldTable) {
      if (newTable && newTable.id !== oldTable?.id) {
        await this.reload(newTable);
      } else if (!newTable) {
        this.columns = [];
        this.dbColumns = [];
        this.mergedColumns = [];
      }
    },
  },
};
</script>
