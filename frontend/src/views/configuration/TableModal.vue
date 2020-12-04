<template>
  <b-modal id="table-modal"
           :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card" style="width: auto">
      <b-loading :active="isLoading" :is-full-page="false"/>

      <header class="modal-card-head">
        <p class="modal-card-title">{{title}}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>

      <section class="modal-card-body">
        <b-field v-if="showTableSelect" label="Table">
          <b-select v-model="internalTable.name"
                    placeholder="Select a table"
                    required
                    validation-message="Select a table to add"
                    expanded>
            <option v-for="(table, index) in tables" :key="index" :value="table.name">
              {{ table.name }}
            </option>
          </b-select>
        </b-field>

        <b-field label="Kafka-Topic">
          <b-input placeholder="Enter Kafka-Topic"
                   :required="!schema.topic && !internalTable.topic"
                   validation-message="Add a topic to the table because the schema has none"
                   v-model="internalTable.topic"/>
        </b-field>

        <b-field label="Record Transaction-ID">
          <b-switch v-model="internalTable.yn_record_txid"
                    @input="onRecordTxIdChanged"
                    true-value="Y"
                    false-value="N"/>
        </b-field>

        <b-field label="Kafka Key Handling">
          <b-field>
            <b-select v-model="internalTable.kafka_key_handling" expanded>
              <option v-for="option in kafkaKeyHandlingOptions" :key="option.value" :value="option.value" :disabled="optionDisabled(option.value)">
                {{ option.label }}
              </option>
            </b-select>
            <b-field v-if="internalTable.kafka_key_handling === 'F'">
              <b-input v-model="internalTable.fixed_message_key"
                       placeholder="Fixed Message Key"
                       required/>
            </b-field>
          </b-field>
        </b-field>

        <b-field label="Info">
          <b-input type="textarea"
                   rows="1"
                   v-model="internalTable.info"
                   required
                   validation-message="Add an info text why this table is used in TriXX"/>
        </b-field>

        <template v-if="!isAddMode">
          <b-field label="Date Of Last Trigger Deployment" custom-class="is-small" class="trigger-dates">
            <div class="columns is-1 is-variable">
              <div class="column">
                <b-field label="Insert" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_insert_trigger_changed_at"/>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Update" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_update_trigger_changed_at"/>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Delete" custom-class="is-small has-text-grey">
                  <b-input size="is-small" disabled :value="triggerDates.youngest_delete_trigger_changed_at"/>
                </b-field>
              </div>
            </div>
          </b-field>
        </template>
      </section>

      <footer class="modal-card-foot" :class="isAddMode ? 'flex-end' : 'space-between'">
        <b-button v-if="!isAddMode"
                  id="delete-table-button"
                  type="is-danger"
                  @click="onRemove">
          Remove from observation
        </b-button>
        <b-button id="save-table-button"
                  type="is-primary"
                  @click="onSave">
          Save
        </b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'TableModal',
  props: {
    tables: { type: Array, default: () => [] },
    table: { type: Object, default: () => {} },
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      isLoading: false,
      internalTable: { ...this.table },
      triggerDates: {},
      kafkaKeyHandlingOptions: [
        { value: 'N', label: 'None' },
        { value: 'F', label: 'Fixed Key' },
        { value: 'P', label: 'Primary Key' },
        { value: 'T', label: 'Transaction-ID' },
      ],
    };
  },
  async created() {
    if (!this.isAddMode) {
      this.triggerDates = await CRUDService.tables.triggerDates(this.table.id);
      if (!this.triggerDates.youngest_insert_trigger_changed_at) {
        this.triggerDates.youngest_insert_trigger_changed_at = 'never';
      }
      if (!this.triggerDates.youngest_update_trigger_changed_at) {
        this.triggerDates.youngest_update_trigger_changed_at = 'never';
      }
      if (!this.triggerDates.youngest_delete_trigger_changed_at) {
        this.triggerDates.youngest_delete_trigger_changed_at = 'never';
      }
    }
  },
  computed: {
    title() {
      if (this.isAddMode) {
        return 'Add table to observe';
      }
      return `Edit observed table (${this.internalTable.name})`;
    },
    showTableSelect() {
      return this.isAddMode;
    },
    isAddMode() {
      return this.table.id === null;
    },
  },
  methods: {
    optionDisabled(value) {
      return value === 'T' && this.internalTable.yn_record_txid === 'N';
    },
    onRecordTxIdChanged(value) {
      // reset 'kafka_key_handling' to N(one) if recording of transaction id changed to disabled
      // and 'kafka_key_handling' is currently T(ransaction)
      if (value === 'N' && this.internalTable.kafka_key_handling === 'T') {
        this.internalTable.kafka_key_handling = 'N';
      }
    },
    onClose() {
      this.$emit('close');
    },
    async onRemove() {
      try {
        this.isLoading = true;
        await CRUDService.tables.delete(this.internalTable.id, this.internalTable);
        this.$emit('removed', this.internalTable);
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
    async onSave() {
      const invalidElements = this.$el.querySelectorAll(':invalid');
      if (invalidElements.length > 0) {
        invalidElements.forEach((e) => e.reportValidity());
        return;
      }

      try {
        if (this.internalTable.id) {
          const updatedTable = await CRUDService.tables.update(this.internalTable.id, { table: this.internalTable });
          this.$emit('updated', updatedTable);
        } else {
          const createdTable = await CRUDService.tables.create({ table: this.internalTable });
          this.$emit('created', createdTable);
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
  },
};
</script>

<style lang="scss" scoped>
  .space-between {
    justify-content: space-between;
  }
  .flex-end {
    justify-content: flex-end;
  }
  .trigger-dates {
    margin-top: 2rem;
  }
  select {
    option[disabled] {
      color: darkgray;
    }
  }
</style>
